# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Audit
        def self.registered(app) # rubocop:disable Metrics/AbcSize
          app.get '/api/audit' do
            require_data!
            dataset = Legion::Data::Model::AuditLog.order(Sequel.desc(:id))
            dataset = dataset.where(event_type: params[:event_type])     if params[:event_type]
            dataset = dataset.where(principal_id: params[:principal_id]) if params[:principal_id]
            dataset = dataset.where(source: params[:source])             if params[:source]
            dataset = dataset.where(status: params[:status])             if params[:status]
            dataset = dataset.where { created_at >= Time.parse(params[:since]) } if params[:since]
            dataset = dataset.where { created_at <= Time.parse(params[:until]) } if params[:until]
            json_collection(dataset)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/audit: #{e.class} — #{e.message}"
            json_error('audit_error', e.message, status_code: 500)
          end

          app.get '/api/audit/verify' do
            require_data!
            unless defined?(Legion::Extensions::Audit::Runners::Audit)
              Legion::Logging.warn 'API GET /api/audit/verify returned 503: lex-audit is not loaded'
              halt 503, json_error('unavailable', 'lex-audit is not loaded', status_code: 503)
            end

            runner = Object.new.extend(Legion::Extensions::Audit::Runners::Audit)
            result = runner.verify
            json_response(result)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/audit/verify: #{e.class} — #{e.message}"
            json_error('audit_error', e.message, status_code: 500)
          end
        end
      end
    end
  end
end
