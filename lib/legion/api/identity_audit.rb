# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module IdentityAudit
        def self.registered(app)
          app.get '/api/identity/audit' do
            unless defined?(Legion::Data::Model::AuditRecord)
              halt 503, json_error('unavailable', 'audit records not available')
            end

            dataset = Legion::Data::Model::AuditRecord.where(entity_type: 'identity')

            principal = params[:principal]
            dataset = dataset.where(Sequel.lit("metadata->>'principal' = ?", principal)) if principal

            since = params[:since]
            if since
              duration = parse_since_duration(since)
              dataset = dataset.where { created_at >= Time.now - duration } if duration
            end

            records = dataset.order(Sequel.desc(:created_at)).limit(100).all
            json_collection(records.map do |r|
              { id: r.id, action: r.action, entity_type: r.entity_type, metadata: r.parsed_metadata, created_at: r.created_at }
            end)
          end

          private

          def parse_since_duration(value)
            return nil unless value.is_a?(String)

            case value
            when /\A(\d+)h\z/ then Regexp.last_match(1).to_i * 3600
            when /\A(\d+)m\z/ then Regexp.last_match(1).to_i * 60
            when /\A(\d+)s\z/ then Regexp.last_match(1).to_i
            when /\A(\d+)d\z/ then Regexp.last_match(1).to_i * 86_400
            end
          end
        end
      end
    end
  end
end
