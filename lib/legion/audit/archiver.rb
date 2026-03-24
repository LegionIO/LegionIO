# frozen_string_literal: true

require 'zlib'
require 'stringio'
require_relative 'hash_chain'
require_relative 'siem_export'
require_relative 'cold_storage'

module Legion
  module Audit
    module Archiver
      module_function

      def enabled?
        Legion::Settings[:audit]&.dig(:retention, :enabled) == true
      end

      def hot_days
        Legion::Settings[:audit]&.dig(:retention, :hot_days) || 90
      end

      def warm_days
        Legion::Settings[:audit]&.dig(:retention, :warm_days) || 365
      end

      def verify_on_archive?
        Legion::Settings[:audit]&.dig(:retention, :verify_on_archive) != false
      end

      # hot -> warm: move audit_log rows older than hot_days to audit_log_archive
      def archive_to_warm(cutoff_days: hot_days)
        return { moved: 0, skipped: true } unless enabled?

        result = Legion::Data::Retention.archive_old_records(
          table: :audit_log,
          archive_after_days: cutoff_days
        )
        { moved: result[:archived], from: :hot, to: :warm }
      end

      # warm -> cold: export audit_log_archive rows older than warm_days to compressed JSONL,
      # upload to cold storage, record manifest, delete from warm after checksum verification
      def archive_to_cold(cutoff_days: warm_days) # rubocop:disable Metrics/MethodLength
        return { moved: 0, skipped: true } unless enabled?

        db = Legion::Data.connection
        return { moved: 0, error: 'no_db' } unless db&.table_exists?(:audit_log_archive)

        cutoff = Time.now - (cutoff_days * 86_400)
        dataset = db[:audit_log_archive].where(::Sequel.lit('created_at < ?', cutoff))
        count = dataset.count
        return { moved: 0 } if count.zero?

        records = dataset.order(:id).all
        ndjson  = Legion::Audit::SiemExport.to_ndjson(records.map { |r| r.is_a?(Hash) ? r : r.values })
        gz_data = compress(ndjson)
        checksum = ::Digest::SHA256.hexdigest(gz_data)

        path = cold_path(records)
        Legion::Audit::ColdStorage.upload(data: gz_data, path: path)

        write_manifest(
          tier:        'cold',
          storage_url: path,
          start_date:  records.first[:created_at],
          end_date:    records.last[:created_at],
          entry_count: count,
          checksum:    checksum,
          first_hash:  records.first[:record_hash].to_s,
          last_hash:   records.last[:record_hash].to_s
        )

        dataset.delete
        log_info "Archived #{count} warm audit records to cold: #{path}"
        { moved: count, path: path, checksum: checksum }
      end

      # verify hash chain integrity for a given tier across an optional date range
      def verify_chain(tier: :hot, start_date: nil, end_date: nil)
        records = load_records_for_tier(tier: tier, start_date: start_date, end_date: end_date)
        Legion::Audit::HashChain.verify_chain(records)
      end

      def cold_storage_url
        Legion::Settings[:audit]&.dig(:retention, :cold_storage) || '/var/lib/legion/audit-archive/'
      end

      def cold_path(records)
        ts = records.first[:created_at]
        stamp = ts.respond_to?(:strftime) ? ts.strftime('%Y%m%d') : ts.to_s[0, 8].tr('-', '')
        ::File.join(cold_storage_url, "audit_cold_#{stamp}_#{records.last[:id]}.jsonl.gz")
      end

      def compress(text)
        sio = ::StringIO.new
        gz  = ::Zlib::GzipWriter.new(sio)
        gz.write(text)
        gz.close
        sio.string
      end

      def write_manifest(tier:, storage_url:, start_date:, end_date:, entry_count:, checksum:, first_hash:, last_hash:)
        db = Legion::Data.connection
        return unless db&.table_exists?(:audit_archive_manifests)

        db[:audit_archive_manifests].insert(
          tier:        tier,
          storage_url: storage_url,
          start_date:  start_date,
          end_date:    end_date,
          entry_count: entry_count,
          checksum:    checksum,
          first_hash:  first_hash,
          last_hash:   last_hash,
          archived_at: Time.now.utc
        )
      end

      def load_records_for_tier(tier:, start_date: nil, end_date: nil)
        db = Legion::Data.connection
        table = tier.to_sym == :hot ? :audit_log : :audit_log_archive
        return [] unless db&.table_exists?(table)

        ds = db[table].order(:id)
        ds = ds.where(::Sequel.lit('created_at >= ?', start_date)) if start_date
        ds = ds.where(::Sequel.lit('created_at <= ?', end_date)) if end_date
        ds.all
      end

      def log_info(msg)
        Legion::Logging.info("[Audit::Archiver] #{msg}") if defined?(Legion::Logging)
      end
    end
  end
end
