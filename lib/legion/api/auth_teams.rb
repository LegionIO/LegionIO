# frozen_string_literal: true

require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthTeams
        # In-memory pending auth states (state -> { verifier:, created_at:, result: })
        @pending = {}
        @mutex = Mutex.new

        class << self
          attr_reader :pending, :mutex
        end

        def self.registered(app)
          register_store_helper(app)
          register_authorize(app)
          register_status(app)
          register_callback(app)
        end

        def self.register_authorize(app)
          app.post '/api/auth/teams/authorize' do
            teams_settings = Legion::Settings[:microsoft_teams] || {}
            auth_settings = teams_settings[:auth] || {}

            tenant_id = teams_settings[:tenant_id] || auth_settings[:tenant_id]
            client_id = teams_settings[:client_id] || auth_settings[:client_id]

            halt 422, json_error('missing_config', 'microsoft_teams.tenant_id and client_id required', status_code: 422) unless tenant_id && client_id

            body = parse_request_body
            delegated = auth_settings[:delegated] || {}
            scopes = body[:scopes] || delegated[:scopes] ||
                     'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

            state = SecureRandom.hex(32)
            verifier = SecureRandom.urlsafe_base64(32)
            challenge = Base64.urlsafe_encode64(
              Digest::SHA256.digest(verifier), padding: false
            )

            port = Legion::Settings.dig(:api, :port) || 4567
            redirect_uri = "http://127.0.0.1:#{port}/api/auth/teams/callback"

            authorize_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?" \
                            "client_id=#{client_id}&response_type=code&redirect_uri=#{::URI.encode_www_form_component(redirect_uri)}" \
                            "&scope=#{::URI.encode_www_form_component(scopes)}" \
                            "&state=#{state}&code_challenge=#{challenge}&code_challenge_method=S256"

            AuthTeams.mutex.synchronize do
              AuthTeams.pending[state] = { verifier: verifier, created_at: Time.now, result: nil,
                                           tenant_id: tenant_id, client_id: client_id,
                                           redirect_uri: redirect_uri, scopes: scopes }
            end

            json_response({ authorize_url: authorize_url, state: state })
          end
        end

        def self.register_status(app)
          app.get '/api/auth/teams/status' do
            state = params[:state]
            halt 422, json_error('missing_state', 'state parameter required', status_code: 422) unless state

            entry = AuthTeams.mutex.synchronize { AuthTeams.pending[state] }
            halt 404, json_error('unknown_state', 'no pending auth for this state', status_code: 404) unless entry

            if entry[:result]
              AuthTeams.mutex.synchronize { AuthTeams.pending.delete(state) }
              json_response(entry[:result])
            else
              json_response({ authenticated: false, waiting: true })
            end
          end
        end

        def self.register_callback(app)
          app.get '/api/auth/teams/callback' do
            code = params[:code]
            state = params[:state]
            error = params[:error]

            entry = AuthTeams.mutex.synchronize { AuthTeams.pending[state] }

            if error || !entry
              msg = error || 'unknown state'
              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: msg } } if entry
              content_type :html
              return '<html><body><h2>Authentication failed.</h2><p>You can close this tab.</p></body></html>'
            end

            # Exchange code for token
            require 'net/http'
            token_uri = ::URI.parse("https://login.microsoftonline.com/#{entry[:tenant_id]}/oauth2/v2.0/token")
            token_response = ::Net::HTTP.post_form(token_uri, {
                                                     'client_id'     => entry[:client_id],
                                                     'grant_type'    => 'authorization_code',
                                                     'code'          => code,
                                                     'redirect_uri'  => entry[:redirect_uri],
                                                     'code_verifier' => entry[:verifier],
                                                     'scope'         => entry[:scopes]
                                                   })

            token_body = Legion::JSON.load(token_response.body)

            if token_body[:access_token]
              # Store token via TokenCache if available
              store_teams_token(token_body, entry[:scopes])
              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: true } }
              content_type :html
              '<html><body><h2>Authentication successful!</h2><p>You can close this tab.</p></body></html>'
            else
              err = token_body[:error_description] || token_body[:error] || 'token exchange failed'
              Legion::Logging.error "Teams OAuth token exchange failed: #{err}" if defined?(Legion::Logging)
              AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: err } }
              content_type :html
              "<html><body><h2>Authentication failed.</h2><p>#{err}</p></body></html>"
            end
          rescue StandardError => e
            Legion::Logging.error "Teams OAuth callback error: #{e.message}" if defined?(Legion::Logging)
            AuthTeams.mutex.synchronize { entry[:result] = { authenticated: false, error: e.message } } if entry
            content_type :html
            '<html><body><h2>Authentication error.</h2><p>Check daemon logs.</p></body></html>'
          end
        end

        def self.register_store_helper(app)
          app.helpers do
            def store_teams_token(token_body, scopes)
              require 'legion/extensions/microsoft_teams/helpers/token_cache'
              cache = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
              cache.store_delegated_token(
                access_token:  token_body[:access_token],
                refresh_token: token_body[:refresh_token],
                expires_in:    token_body[:expires_in] || 3600,
                scopes:        scopes
              )
              cache.save_to_vault
              Legion::Logging.info 'Teams delegated token stored' if defined?(Legion::Logging)
            rescue StandardError => e
              Legion::Logging.warn "Failed to store Teams token: #{e.message}" if defined?(Legion::Logging)
            end
          end
        end

        class << self
          private :register_authorize, :register_status, :register_callback, :register_store_helper
        end
      end
    end
  end
end
