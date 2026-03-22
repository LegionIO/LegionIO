# frozen_string_literal: true

require 'net/http'
require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthHuman
        def self.registered(app)
          register_authorize(app)
          register_callback(app)
        end

        def self.resolve_entra_settings
          return {} unless defined?(Legion::Settings)

          rbac = Legion::Settings[:rbac]
          entra = rbac.is_a?(Hash) ? rbac[:entra] : nil
          return entra if entra.is_a?(Hash)

          {}
        rescue StandardError
          {}
        end

        def self.exchange_code(entra, code)
          uri = URI("https://login.microsoftonline.com/#{entra[:tenant_id]}/oauth2/v2.0/token")
          response = Net::HTTP.post_form(uri, {
                                           'client_id'     => entra[:client_id],
                                           'client_secret' => entra[:client_secret],
                                           'code'          => code,
                                           'redirect_uri'  => entra[:redirect_uri],
                                           'grant_type'    => 'authorization_code'
                                         })

          return nil unless response.is_a?(Net::HTTPSuccess)

          Legion::JSON.load(response.body)
        rescue StandardError
          nil
        end

        def self.register_authorize(app)
          app.get '/api/auth/authorize' do
            entra = Routes::AuthHuman.resolve_entra_settings
            unless entra[:tenant_id] && entra[:client_id]
              Legion::Logging.error 'API GET /api/auth/authorize returned 500: Entra OAuth settings are missing'
              halt 500, json_error('entra_not_configured', 'Entra OAuth settings are missing', status_code: 500)
            end

            state = Legion::Crypt::JWT.issue(
              { nonce: SecureRandom.hex(16), purpose: 'oauth_state' },
              ttl: 300
            )

            query = URI.encode_www_form({
                                          'client_id'     => entra[:client_id],
                                          'redirect_uri'  => entra[:redirect_uri],
                                          'response_type' => 'code',
                                          'scope'         => 'openid profile',
                                          'state'         => state
                                        })

            redirect "https://login.microsoftonline.com/#{entra[:tenant_id]}/oauth2/v2.0/authorize?#{query}"
          end
        end

        def self.register_callback(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.get '/api/auth/callback' do
            entra = Routes::AuthHuman.resolve_entra_settings
            unless entra[:tenant_id] && entra[:client_id]
              Legion::Logging.error 'API GET /api/auth/callback returned 500: Entra OAuth settings are missing'
              halt 500, json_error('entra_not_configured', 'Entra OAuth settings are missing', status_code: 500)
            end

            if params[:error]
              Legion::Logging.warn "API GET /api/auth/callback returned 400: #{params[:error_description] || params[:error]}"
              halt 400, json_error('oauth_error', params[:error_description] || params[:error], status_code: 400)
            end
            unless params[:code]
              Legion::Logging.warn 'API GET /api/auth/callback returned 400: authorization code is required'
              halt 400, json_error('missing_code', 'authorization code is required', status_code: 400)
            end

            if params[:state]
              begin
                Legion::Crypt::JWT.verify(params[:state])
              rescue Legion::Crypt::JWT::Error
                Legion::Logging.warn 'API GET /api/auth/callback returned 400: CSRF state token is invalid or expired'
                halt 400, json_error('invalid_state', 'CSRF state token is invalid or expired', status_code: 400)
              end
            end

            token_response = Routes::AuthHuman.exchange_code(entra, params[:code])
            unless token_response
              Legion::Logging.error 'API GET /api/auth/callback returned 502: Failed to exchange code for tokens'
              halt 502, json_error('token_exchange_failed', 'Failed to exchange code for tokens', status_code: 502)
            end

            id_token = token_response[:id_token] || token_response['id_token']
            unless id_token
              Legion::Logging.error 'API GET /api/auth/callback returned 502: Entra did not return an id_token'
              halt 502, json_error('no_id_token', 'Entra did not return an id_token', status_code: 502)
            end

            jwks_url = "https://login.microsoftonline.com/#{entra[:tenant_id]}/discovery/v2.0/keys"
            issuer = "https://login.microsoftonline.com/#{entra[:tenant_id]}/v2.0"

            begin
              claims = Legion::Crypt::JWT.verify_with_jwks(id_token, jwks_url: jwks_url, issuers: [issuer])
            rescue Legion::Crypt::JWT::Error => e
              Legion::Logging.warn "API GET /api/auth/callback returned 401: #{e.message}"
              halt 401, json_error('invalid_id_token', e.message, status_code: 401)
            end

            unless defined?(Legion::Rbac::EntraClaimsMapper)
              halt 501, json_error('claims_mapper_not_available', 'EntraClaimsMapper is not loaded', status_code: 501)
            end

            mapped = Legion::Rbac::EntraClaimsMapper.map_claims(
              claims,
              role_map:     entra[:role_map] || Legion::Rbac::EntraClaimsMapper::DEFAULT_ROLE_MAP,
              group_map:    entra[:group_map] || {},
              default_role: entra[:default_role] || 'worker'
            )

            ttl = 28_800
            token = Legion::API::Token.issue_human_token(
              msid: mapped[:sub], name: mapped[:name], roles: mapped[:roles], ttl: ttl
            )

            Legion::Logging.info "API: human OAuth callback issued token for sub=#{mapped[:sub]}"
            if request.env['HTTP_ACCEPT']&.include?('application/json')
              json_response({
                              access_token: token,
                              token_type:   'Bearer',
                              expires_in:   ttl,
                              roles:        mapped[:roles],
                              name:         mapped[:name]
                            })
            else
              redirect_url = entra[:success_redirect] || '/api/health'
              redirect "#{redirect_url}#access_token=#{token}"
            end
          end
        end

        class << self
          private :register_authorize, :register_callback
        end
      end
    end
  end
end
