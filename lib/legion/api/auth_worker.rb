# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthWorker
        def self.registered(app)
          register_worker_token_exchange(app)
        end

        def self.register_worker_token_exchange(app) # rubocop:disable Metrics/MethodLength
          app.post '/api/auth/worker-token' do
            body = parse_request_body
            grant_type = body[:grant_type]
            entra_token = body[:entra_token]

            unless grant_type == 'client_credentials'
              halt 400, json_error('unsupported_grant_type', 'grant_type must be client_credentials',
                                   status_code: 400)
            end

            halt 400, json_error('missing_entra_token', 'entra_token is required', status_code: 400) unless entra_token

            unless defined?(Legion::Crypt::JWT) && Legion::Crypt::JWT.respond_to?(:verify_with_jwks)
              halt 501, json_error('jwks_validation_not_available',
                                   'JWKS validation is not available', status_code: 501)
            end

            entra_settings = Routes::AuthWorker.resolve_entra_settings
            tenant_id = entra_settings[:tenant_id]
            unless tenant_id
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
              halt 401, json_error('token_expired', 'Entra token has expired', status_code: 401)
            rescue Legion::Crypt::JWT::InvalidTokenError => e
              halt 401, json_error('invalid_token', e.message, status_code: 401)
            rescue Legion::Crypt::JWT::Error => e
              halt 502, json_error('identity_provider_unavailable', e.message, status_code: 502)
            end

            app_id = claims[:appid] || claims[:azp] || claims['appid'] || claims['azp']
            halt 401, json_error('invalid_token', 'missing appid claim', status_code: 401) unless app_id

            halt 503, json_error('data_unavailable', 'legion-data not connected', status_code: 503) unless defined?(Legion::Data::Model::DigitalWorker)

            worker = Legion::Data::Model::DigitalWorker.first(entra_app_id: app_id)
            unless worker
              halt 404, json_error('worker_not_found',
                                   "no worker registered for entra_app_id #{app_id}", status_code: 404)
            end

            unless worker.lifecycle_state == 'active'
              halt 403, json_error('worker_not_active',
                                   "worker is in #{worker.lifecycle_state} state", status_code: 403)
            end

            ttl = 3600
            token = Legion::API::Token.issue_worker_token(
              worker_id: worker.worker_id, owner_msid: worker.owner_msid, ttl: ttl
            )

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
        rescue StandardError
          {}
        end

        class << self
          private :register_worker_token_exchange
        end
      end
    end
  end
end
