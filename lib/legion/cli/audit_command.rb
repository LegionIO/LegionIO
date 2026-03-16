# frozen_string_literal: true

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

      desc 'verify', 'Verify audit log hash chain integrity'
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
    end
  end
end
