# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthWorker
        def self.registered(app)
          register_worker_token_exchange(app)
        end

        def self.register_worker_token_exchange(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.post '/api/auth/worker-token' do
            Legion::Logging.debug "API: POST /api/auth/worker-token params=#{params.keys}"
            body = parse_request_body
            grant_type = body[:grant_type]
            entra_token = body[:entra_token]

            unless grant_type == 'client_credentials'
              Legion::Logging.warn "API POST /api/auth/worker-token returned 400: unsupported grant_type=#{grant_type}"
              halt 400, json_error('unsupported_grant_type', 'grant_type must be client_credentials',
                                   status_code: 400)
            end

            unless entra_token
              Legion::Logging.warn 'API POST /api/auth/worker-token returned 400: entra_token is required'
              halt 400, json_error('missing_entra_token', 'entra_token is required', status_code: 400)
            end

            unless defined?(Legion::Crypt::JWT) && Legion::Crypt::JWT.respond_to?(:verify_with_jwks)
              halt 501, json_error('jwks_validation_not_available',
                                   'JWKS validation is not available', status_code: 501)
            end

            entra_settings = Routes::AuthWorker.resolve_entra_settings
            tenant_id = entra_settings[:tenant_id]
            unless tenant_id
              Legion::Logging.error 'API POST /api/auth/worker-token returned 500: Entra tenant_id is not configured'
              halt 500, json_error('entra_tenant_not_configured',
                                   'Entra tenant_id is not configured', status_code: 500)
            end

            jwks_url = "https://login.microsoftonline.com/#{tenant_id}/discovery/v2.0/keys"
            issuer = "https://login.microsoftonline.com/#{tenant_id}/v2.0"

            begin
              claims = Legion::Crypt::JWT.verify_with_jwks(
                entra_token, jwks_url: jwks_url, issuers: [issuer]
              )
            rescue Legion::Crypt::JWT::ExpiredTokenError
              Legion::Logging.warn 'API POST /api/auth/worker-token returned 401: Entra token has expired'
              halt 401, json_error('token_expired', 'Entra token has expired', status_code: 401)
            rescue Legion::Crypt::JWT::InvalidTokenError => e
              Legion::Logging.warn "API POST /api/auth/worker-token returned 401: #{e.message}"
              halt 401, json_error('invalid_token', e.message, status_code: 401)
            rescue Legion::Crypt::JWT::Error => e
              Legion::Logging.error "API POST /api/auth/worker-token returned 502: #{e.message}"
              halt 502, json_error('identity_provider_unavailable', e.message, status_code: 502)
            end

            app_id = claims[:appid] || claims[:azp] || claims['appid'] || claims['azp']
            unless app_id
              Legion::Logging.warn 'API POST /api/auth/worker-token returned 401: missing appid claim'
              halt 401, json_error('invalid_token', 'missing appid claim', status_code: 401)
            end

            halt 503, json_error('data_unavailable', 'legion-data not connected', status_code: 503) unless defined?(Legion::Data::Model::DigitalWorker)

            worker = Legion::Data::Model::DigitalWorker.first(entra_app_id: app_id)
            unless worker
              Legion::Logging.warn "API POST /api/auth/worker-token returned 404: no worker for entra_app_id=#{app_id}"
              halt 404, json_error('worker_not_found',
                                   "no worker registered for entra_app_id #{app_id}", status_code: 404)
            end

            unless worker.lifecycle_state == 'active'
              Legion::Logging.warn "API POST /api/auth/worker-token returned 403: worker #{worker.worker_id} is in #{worker.lifecycle_state} state"
              halt 403, json_error('worker_not_active',
                                   "worker is in #{worker.lifecycle_state} state", status_code: 403)
            end

            ttl = 3600
            token = Legion::API::Token.issue_worker_token(
              worker_id: worker.worker_id, owner_msid: worker.owner_msid, ttl: ttl
            )

            Legion::Logging.info "API: issued worker token for worker_id=#{worker.worker_id}"
            json_response({
                            access_token: token,
                            token_type:   'Bearer',
                            expires_in:   ttl,
                            worker_id:    worker.worker_id,
                            scope:        'worker'
                          })
          end
        end

        def self.resolve_entra_settings
          return {} unless defined?(Legion::Settings)

          identity = Legion::Settings[:identity]
          entra = identity.is_a?(Hash) ? identity[:entra] : nil
          return entra if entra.is_a?(Hash)

          rbac = Legion::Settings[:rbac]
          entra = rbac.is_a?(Hash) ? rbac[:entra] : nil
          return entra if entra.is_a?(Hash)

          {}
        rescue StandardError => e
          Legion::Logging.debug "AuthWorker#resolve_entra_settings failed: #{e.message}" if defined?(Legion::Logging)
          {}
        end

        class << self
          private :register_worker_token_exchange
        end
      end
    end
  end
end
