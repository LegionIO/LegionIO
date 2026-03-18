# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthKerberos
        def self.registered(app)
          register_negotiate(app)
        end

        def self.resolve_kerberos_role_map
          return {} unless defined?(Legion::Settings)

          Legion::Settings.dig(:kerberos, :role_map) || {}
        rescue StandardError
          {}
        end

        def self.kerberos_available?
          defined?(Legion::Extensions::Kerberos::Client) &&
            defined?(Legion::Rbac::KerberosClaimsMapper)
        end

        def self.register_negotiate(app)
          app.get '/api/auth/negotiate' do
            auth_header = request.env['HTTP_AUTHORIZATION']

            unless auth_header&.match?(/\ANegotiate\s+/i)
              headers['WWW-Authenticate'] = 'Negotiate'
              halt 401, json_error('negotiate_required', 'Negotiate token required', status_code: 401)
            end

            halt 501, json_error('kerberos_not_available', 'Kerberos extension is not loaded', status_code: 501) unless Routes::AuthKerberos.kerberos_available?

            token = auth_header.sub(/\ANegotiate\s+/i, '')

            auth_result = begin
              client = Legion::Extensions::Kerberos::Client.new
              client.authenticate(token: token)
            rescue StandardError
              nil
            end

            unless auth_result&.dig(:success)
              headers['WWW-Authenticate'] = 'Negotiate'
              halt 401, json_error('kerberos_auth_failed', 'Kerberos authentication failed', status_code: 401)
            end

            role_map = Routes::AuthKerberos.resolve_kerberos_role_map
            profile = auth_result.slice(:first_name, :last_name, :email, :display_name)
            mapped = Legion::Rbac::KerberosClaimsMapper.map_with_fallback(
              principal: auth_result[:principal],
              groups:    auth_result[:groups] || [],
              role_map:  role_map,
              **profile
            )

            display = mapped[:display_name] || mapped[:first_name]
            ttl = 28_800
            legion_token = Legion::API::Token.issue_human_token(
              msid: mapped[:sub], name: display, roles: mapped[:roles], ttl: ttl
            )

            output_token = auth_result[:output_token]
            headers['WWW-Authenticate'] = "Negotiate #{output_token}" if output_token

            json_response({
                            token:       legion_token,
                            principal:   auth_result[:principal],
                            roles:       mapped[:roles],
                            auth_method: 'kerberos',
                            **profile
                          })
          end
        end

        class << self
          private :register_negotiate
        end
      end
    end
  end
end
