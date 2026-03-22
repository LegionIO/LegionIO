# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Webhooks
        def self.registered(app)
          app.get '/api/webhooks' do
            json_response(Legion::Webhooks.list)
          end

          app.post '/api/webhooks' do
            Legion::Logging.debug "API: POST /api/webhooks params=#{params.keys}"
            body = parse_request_body
            result = Legion::Webhooks.register(
              url: body[:url], secret: body[:secret],
              event_types: body[:event_types] || ['*'],
              max_retries: body[:max_retries] || 5
            )
            Legion::Logging.info "API: registered webhook for url=#{body[:url]} events=#{(body[:event_types] || ['*']).join(',')}"
            json_response(result, status_code: 201)
          end

          app.delete '/api/webhooks/:id' do
            result = Legion::Webhooks.unregister(id: params[:id].to_i)
            Legion::Logging.info "API: deleted webhook #{params[:id]}"
            json_response(result)
          end
        end
      end
    end
  end
end
