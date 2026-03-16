# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module OAuth
        def self.registered(app)
          register_callback(app)
        end

        def self.register_callback(app)
          app.get '/api/oauth/microsoft_teams/callback' do
            content_type :html
            code  = params['code']
            state = params['state']

            unless code && state
              status 400
              return '<html><body><h2>Missing code or state parameter</h2></body></html>'
            end

            Legion::Events.emit('microsoft_teams.oauth.callback', code: code, state: state)

            <<~HTML
              <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
              <h2>Authentication complete</h2>
              <p>You can close this window.</p>
              </body></html>
            HTML
          end
        end

        class << self
          private :register_callback
        end
      end
    end
  end
end
