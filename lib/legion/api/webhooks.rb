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
            body = parse_request_body
            result = Legion::Webhooks.register(
              url: body[:url], secret: body[:secret],
              event_types: body[:event_types] || ['*'],
              max_retries: body[:max_retries] || 5
            )
            json_response(result, status_code: 201)
          end

          app.delete '/api/webhooks/:id' do
            json_response(Legion::Webhooks.unregister(id: params[:id].to_i))
          end
        end
      end
    end
  end
end
