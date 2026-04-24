# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module IdentityAudit
        def self.registered(app)
          app.helpers IdentityAuditHelpers

          app.get '/api/identity/audit' do
            require_data!
            halt 503, json_error('unavailable', 'identity audit log not available') unless defined?(Legion::Data::Model::IdentityAuditLog)

            dataset = Legion::Data::Model::IdentityAuditLog.dataset

            principal = params[:principal]
            if principal && defined?(Legion::Data::Model::Principal)
              principal_record = Legion::Data::Model::Principal.where(canonical_name: principal).first
              halt 404, json_error('not_found', "principal '#{principal}' not found") unless principal_record
              dataset = dataset.where(principal_id: principal_record.id)
            end

            provider = params[:provider]
            dataset = dataset.where(provider_name: provider) if provider

            event_type = params[:event_type]
            dataset = dataset.where(event_type: event_type) if event_type

            since = params[:since]
            if since
              duration = parse_since_duration(since)
              dataset = dataset.where { created_at >= Time.now - duration } if duration
            end

            records = dataset.order(Sequel.desc(:created_at)).limit(100).all
            json_collection(records.map do |r|
              { id: r.id, event_type: r.event_type, provider_name: r.provider_name,
                trust_level: r.trust_level, detail: r.detail,
                node_id: r.node_id, session_id: r.session_id, created_at: r.created_at }
            end)
          end
        end

        module IdentityAuditHelpers
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
