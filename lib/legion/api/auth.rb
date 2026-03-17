# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Auth
        def self.registered(app)
          register_token_exchange(app)
        end

        def self.register_token_exchange(app) # rubocop:disable Metrics/MethodLength
          app.post '/api/auth/token' do
            body = parse_request_body
            grant_type = body[:grant_type]
            subject_token = body[:subject_token]

            unless grant_type == 'urn:ietf:params:oauth:grant-type:token-exchange'
              halt 400, json_error('unsupported_grant_type', 'expected urn:ietf:params:oauth:grant-type:token-exchange',
                                   status_code: 400)
            end

            halt 400, json_error('missing_subject_token', 'subject_token is required', status_code: 400) unless subject_token

            unless defined?(Legion::Crypt::JWT) && Legion::Crypt::JWT.respond_to?(:verify_with_jwks)
              halt 501, json_error('jwks_validation_not_available', 'legion-crypt JWKS support not loaded',
                                   status_code: 501)
            end

            rbac_settings = (Legion::Settings[:rbac].is_a?(Hash) && Legion::Settings[:rbac][:entra]) || {}
            tenant_id = rbac_settings[:tenant_id]
            halt 500, json_error('entra_tenant_not_configured', 'rbac.entra.tenant_id not set', status_code: 500) unless tenant_id

            jwks_url = "https://login.microsoftonline.com/#{tenant_id}/discovery/v2.0/keys"
            issuer = "https://login.microsoftonline.com/#{tenant_id}/v2.0"

            begin
              entra_claims = Legion::Crypt::JWT.verify_with_jwks(
                subject_token, jwks_url: jwks_url, issuers: [issuer]
              )
            rescue Legion::Crypt::JWT::ExpiredTokenError
              halt 401, json_error('token_expired', 'Entra token has expired', status_code: 401)
            rescue Legion::Crypt::JWT::InvalidTokenError => e
              halt 401, json_error('invalid_token', e.message, status_code: 401)
            rescue Legion::Crypt::JWT::Error => e
              halt 502, json_error('identity_provider_unavailable', e.message, status_code: 502)
            end

            unless defined?(Legion::Rbac::EntraClaimsMapper)
              halt 501, json_error('claims_mapper_not_available', 'legion-rbac EntraClaimsMapper not loaded',
                                   status_code: 501)
            end

            mapped = Legion::Rbac::EntraClaimsMapper.map_claims(
              entra_claims,
              role_map:     rbac_settings[:role_map] || Legion::Rbac::EntraClaimsMapper::DEFAULT_ROLE_MAP,
              group_map:    rbac_settings[:group_map] || {},
              default_role: rbac_settings[:default_role] || 'worker'
            )

            ttl = 28_800
            token = Legion::API::Token.issue_human_token(
              msid: mapped[:sub], name: mapped[:name],
              roles: mapped[:roles], ttl: ttl
            )

            json_response({
                            access_token: token,
                            token_type:   'Bearer',
                            expires_in:   ttl,
                            roles:        mapped[:roles],
                            team:         mapped[:team]
                          })
          end
        end

        class << self
          private :register_token_exchange
        end
      end
    end
  end
end
