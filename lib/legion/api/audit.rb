# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Audit
        def self.registered(app)
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
          end

          app.get '/api/audit/verify' do
            require_data!
            halt 503, json_error('unavailable', 'lex-audit is not loaded', status_code: 503) unless defined?(Legion::Extensions::Audit::Runners::Audit)

            runner = Object.new.extend(Legion::Extensions::Audit::Runners::Audit)
            result = runner.verify
            json_response(result)
          end
        end
      end
    end
  end
end
