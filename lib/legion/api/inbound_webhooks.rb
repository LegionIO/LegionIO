# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module InboundWebhooks
        def self.registered(app)
          app.post '/api/webhooks/:source' do
            require 'legion/trigger'

            source_name = params[:source]
            body_raw = request.body.read
            body = begin
              Legion::JSON.load(body_raw)
            rescue StandardError
              body_raw
            end

            headers = request.env.select { |k, _| k.start_with?('HTTP_') }

            result = Legion::Trigger.process(
              source_name: source_name,
              headers:     headers,
              body_raw:    body_raw,
              body:        body
            )

            if result[:success]
              json_response(result, status_code: 202)
            elsif result[:reason] == :duplicate
              json_response(result, status_code: 200)
            elsif result[:reason] == :unknown_source
              halt 404, json_error('unknown_source', result[:error], status_code: 404)
            else
              halt 500, json_error('trigger_error', result[:error] || 'processing failed', status_code: 500)
            end
          end

          app.get '/api/webhooks/sources' do
            require 'legion/trigger'
            json_response({ sources: Legion::Trigger.registered_sources })
          end
        end
      end
    end
  end
end
