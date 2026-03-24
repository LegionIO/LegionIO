# frozen_string_literal: true

require_relative '../audit/archiver'
require_relative '../audit/cold_storage'

module Legion
  module CLI
    class Audit < Thor
      namespace 'audit'

      desc 'list', 'List audit log records'
      option :event_type, type: :string, desc: 'Filter by event type'
      option :principal, type: :string, desc: 'Filter by principal_id'
      option :source, type: :string, desc: 'Filter by source'
      option :status, type: :string, desc: 'Filter by status'
      option :since, type: :string, desc: 'Records after this ISO8601 timestamp'
      option :until, type: :string, desc: 'Records before this ISO8601 timestamp'
      option :limit, type: :numeric, default: 20, desc: 'Number of records'
      option :json, type: :boolean, default: false, desc: 'Output as JSON'
      def list # rubocop:disable Metrics/AbcSize
        Connection.ensure_settings
        Connection.ensure_data

        dataset = Legion::Data::Model::AuditLog.order(Sequel.desc(:id))
        dataset = dataset.where(event_type: options[:event_type]) if options[:event_type]
        dataset = dataset.where(principal_id: options[:principal]) if options[:principal]
        dataset = dataset.where(source: options[:source]) if options[:source]
        dataset = dataset.where(status: options[:status]) if options[:status]
        dataset = dataset.where { created_at >= Time.parse(options[:since]) } if options[:since]
        dataset = dataset.where { created_at <= Time.parse(options[:until]) } if options[:until]
        records = dataset.limit(options[:limit]).all

        if options[:json]
          puts Legion::JSON.dump(records.map(&:values))
        else
          records.each do |r|
            puts "#{r.created_at}  #{r.event_type.ljust(22)} #{r.principal_id.ljust(20)} " \
                 "#{r.action.ljust(12)} #{r.resource.ljust(40)} #{r.status}"
          end
          puts "#{records.count} records shown"
        end
      end

      desc 'verify', 'Verify audit log hash chain integrity (lex-audit runner path)'
      option :json, type: :boolean, default: false, desc: 'Output as JSON'
      def verify
        Connection.ensure_settings
        Connection.ensure_data

        unless defined?(Legion::Extensions::Audit::Runners::Audit)
          puts 'lex-audit is not loaded'
          exit 1
        end

        runner = Object.new.extend(Legion::Extensions::Audit::Runners::Audit)
        result = runner.verify

        if options[:json]
          puts Legion::JSON.dump(result)
        elsif result[:valid]
          puts "Audit chain valid: #{result[:records_checked]} records verified"
        else
          puts "CHAIN BROKEN at record ##{result[:break_at]} (#{result[:records_checked]} records checked before break)"
          exit 1
        end
      end

      desc 'archive', 'Archive audit records across tiers (hot -> warm -> cold)'
      option :dry_run, type: :boolean, default: false, aliases: '--dry-run', desc: 'Preview without executing'
      option :execute, type: :boolean, default: false,                       desc: 'Run archival now'
      option :json,    type: :boolean, default: false,                       desc: 'Output as JSON'
      def archive
        Connection.ensure_settings
        Connection.ensure_data

        unless Legion::Audit::Archiver.enabled?
          puts 'Audit retention is disabled. Set audit.retention.enabled = true to activate.'
          return
        end

        if options[:dry_run]
          status = Legion::Data::Retention.retention_status(table: :audit_log)
          output = {
            mode:         'DRY RUN',
            hot_records:  status[:active_count],
            warm_records: status[:archived_count],
            oldest_hot:   status[:oldest_active]&.to_s,
            oldest_warm:  status[:oldest_archived]&.to_s,
            hot_days:     Legion::Audit::Archiver.hot_days,
            warm_days:    Legion::Audit::Archiver.warm_days
          }
          if options[:json]
            puts Legion::JSON.dump(output)
          else
            puts 'DRY RUN — no records will be moved'
            output.each { |k, v| puts "  #{k}: #{v}" }
          end
          return
        end

        unless options[:execute]
          puts 'Pass --execute to run archival, or --dry-run to preview.'
          return
        end

        warm_result = Legion::Audit::Archiver.archive_to_warm
        puts "Archived #{warm_result[:moved]} records to warm" unless options[:json]

        cold_result = Legion::Audit::Archiver.archive_to_cold
        puts "Archived #{cold_result[:moved]} records to cold: #{cold_result[:path]}" unless options[:json]

        if Legion::Audit::Archiver.verify_on_archive?
          verify_result = Legion::Audit::Archiver.verify_chain(tier: :warm)
          unless options[:json]
            if verify_result[:valid]
              puts "Chain integrity verified: #{verify_result[:records_checked]} warm records"
            else
              puts "WARNING: chain broken in warm tier after archival (#{verify_result[:broken_links].count} links)"
            end
          end
        end

        puts Legion::JSON.dump({ warm: warm_result, cold: cold_result }) if options[:json]
      end

      desc 'verify_chain', 'Verify hash chain integrity for a specific tier and date range'
      option :tier,  type: :string,  default: 'hot', desc: 'Tier to verify: hot, warm'
      option :start, type: :string,  desc: 'ISO8601 start date (inclusive)'
      option :end,   type: :string,  desc: 'ISO8601 end date (inclusive)'
      option :json,  type: :boolean, default: false, desc: 'Output as JSON'
      def verify_chain
        Connection.ensure_settings
        Connection.ensure_data

        tier       = options[:tier].to_sym
        start_date = options[:start] ? Time.parse(options[:start]) : nil
        end_date   = options[:end]   ? Time.parse(options[:end])   : nil

        result = Legion::Audit::Archiver.verify_chain(
          tier:       tier,
          start_date: start_date,
          end_date:   end_date
        )

        if options[:json]
          puts Legion::JSON.dump(result)
        elsif result[:valid]
          puts "Chain valid (#{tier}): #{result[:records_checked]} records verified"
        else
          puts "CHAIN BROKEN in #{tier} tier — #{result[:broken_links].count} broken link(s)"
          result[:broken_links].each { |l| puts "  record ##{l[:id]}: expected #{l[:expected]}, got #{l[:got]}" }
          exit 1
        end
      end

      desc 'restore', 'Restore cold-archived records to warm tier for querying'
      option :date, type: :string, required: true, desc: 'Date stamp of archive to restore (YYYYMMDD or ISO8601)'
      option :json, type: :boolean, default: false, desc: 'Output as JSON'
      def restore
        Connection.ensure_settings
        Connection.ensure_data

        unless Legion::Audit::Archiver.enabled?
          puts 'Audit retention is disabled.'
          return
        end

        db = Legion::Data.connection
        unless db&.table_exists?(:audit_archive_manifests)
          puts 'No archive manifests table found. Has migration 039 been run?'
          exit 1
        end

        date_str = options[:date].tr('-', '')[0, 8]
        manifests = db[:audit_archive_manifests]
                    .where(tier: 'cold')
                    .where(::Sequel.like(:storage_url, "%#{date_str}%"))
                    .all

        if manifests.empty?
          puts "No cold archives found for date: #{options[:date]}"
          exit 1
        end

        restored = 0
        manifests.each do |manifest|
          gz_data = Legion::Audit::ColdStorage.download(path: manifest[:storage_url])
          ndjson  = ::Zlib::GzipReader.new(::StringIO.new(gz_data)).read
          records = ndjson.split("\n").map { |line| Legion::JSON.load(line) }

          db.transaction do
            records.each { |r| db[:audit_log_archive].insert(r.transform_keys(&:to_sym)) }
          end
          restored += records.size
        end

        result = { restored: restored, manifests: manifests.count }
        if options[:json]
          puts Legion::JSON.dump(result)
        else
          puts "Restored #{restored} records from #{manifests.count} cold archive(s) to warm tier"
        end
      end
    end
  end
end
