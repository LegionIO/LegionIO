# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module AuthSaml
        def self.registered(app)
          return unless saml_enabled?

          app.helpers do
            define_method(:saml_settings) { Routes::AuthSaml.build_saml_settings }
          end

          register_metadata(app)
          register_login(app)
          register_acs(app)
        end

        def self.saml_enabled?
          return false unless defined?(OneLogin::RubySaml)

          cfg = resolve_saml_config
          cfg.is_a?(Hash) && cfg[:enabled]
        end

        def self.resolve_saml_config
          return {} unless defined?(Legion::Settings)

          auth = Legion::Settings[:auth]
          saml = auth.is_a?(Hash) ? auth[:saml] : nil
          return saml if saml.is_a?(Hash)

          {}
        rescue StandardError => e
          Legion::Logging.debug "AuthSaml#resolve_saml_config failed: #{e.message}" if defined?(Legion::Logging)
          {}
        end

        def self.build_saml_settings
          cfg = resolve_saml_config

          settings                            = OneLogin::RubySaml::Settings.new
          settings.idp_sso_service_url        = cfg[:idp_sso_url]
          settings.idp_cert                   = cfg[:idp_cert]
          settings.sp_entity_id               = cfg[:sp_entity_id]
          settings.assertion_consumer_service_url = cfg[:sp_acs_url]
          settings.name_identifier_format = cfg[:name_id_format] ||
                                            'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
          settings.security[:authn_requests_signed]   = false
          settings.security[:want_assertions_signed]  = cfg.fetch(:want_assertions_signed, true)
          settings.security[:want_assertions_encrypted] = cfg.fetch(:want_assertions_encrypted, false)
          settings
        end

        def self.register_metadata(app)
          app.get '/api/auth/saml/metadata' do
            halt 503, json_error('saml_not_configured', 'SAML SP is not configured', status_code: 503) unless defined?(OneLogin::RubySaml)

            meta = OneLogin::RubySaml::Metadata.new
            content_type 'application/xml'
            meta.generate(saml_settings, true)
          end
        end

        def self.register_login(app)
          app.get '/api/auth/saml/login' do
            halt 503, json_error('saml_not_configured', 'SAML SP is not configured', status_code: 503) unless defined?(OneLogin::RubySaml)

            cfg = Routes::AuthSaml.resolve_saml_config
            unless cfg[:idp_sso_url] && cfg[:sp_entity_id]
              halt 500, json_error('saml_misconfigured', 'auth.saml.idp_sso_url and sp_entity_id are required',
                                   status_code: 500)
            end

            auth_request = OneLogin::RubySaml::Authrequest.new
            redirect auth_request.create(saml_settings)
          end
        end

        def self.register_acs(app)
          app.post '/api/auth/saml/acs' do
            halt 503, json_error('saml_not_configured', 'SAML SP is not configured', status_code: 503) unless defined?(OneLogin::RubySaml)

            unless params['SAMLResponse']
              halt 400, json_error('missing_saml_response', 'SAMLResponse parameter is required',
                                   status_code: 400)
            end

            response = OneLogin::RubySaml::Response.new(
              params['SAMLResponse'],
              settings: saml_settings
            )

            unless response.is_valid?
              errors = response.errors.join(', ')
              halt 401, json_error('saml_invalid', "SAML assertion is invalid: #{errors}", status_code: 401)
            end

            claims = Routes::AuthSaml.extract_claims(response)
            roles  = Routes::AuthSaml.map_roles(claims[:groups])

            ttl   = 28_800
            token = Legion::API::Token.issue_human_token(
              msid:  claims[:nameid],
              name:  claims[:display_name],
              roles: roles,
              ttl:   ttl
            )

            json_response({
                            access_token: token,
                            token_type:   'Bearer',
                            expires_in:   ttl,
                            roles:        roles,
                            name:         claims[:display_name]
                          })
          end
        end

        def self.extract_claims(response)
          attrs = response.attributes

          email        = first_attr(attrs, 'email', 'mail', 'emailAddress',
                                    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress')
          display_name = first_attr(attrs, 'displayName', 'name',
                                    'http://schemas.microsoft.com/identity/claims/displayname',
                                    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name')
          groups       = multi_attr(attrs, 'groups',
                                    'http://schemas.microsoft.com/ws/2008/06/identity/claims/groups')

          {
            nameid:       response.nameid,
            email:        email,
            display_name: display_name || email,
            groups:       groups
          }
        end

        def self.map_roles(groups)
          if defined?(Legion::Rbac::ClaimsMapper) && Legion::Rbac::ClaimsMapper.respond_to?(:groups_to_roles)
            cfg          = resolve_saml_config
            group_map    = cfg[:group_map] || {}
            default_role = cfg[:default_role] || 'worker'
            Legion::Rbac::ClaimsMapper.groups_to_roles(groups, group_map: group_map, default_role: default_role)
          else
            ['worker']
          end
        end

        class << self
          private

          def first_attr(attrs, *names)
            names.each do |n|
              v = safe_attr(attrs, n)
              return v if v
            end
            nil
          end

          def multi_attr(attrs, *names)
            names.each do |n|
              v = attrs.multi(n)
              return Array(v) if v
            rescue StandardError => e
              Legion::Logging.debug "AuthSaml#multi_attr failed for attr=#{n}: #{e.message}" if defined?(Legion::Logging)
              nil
            end
            []
          end

          def safe_attr(attrs, name)
            attrs[name]
          rescue StandardError => e
            Legion::Logging.debug "AuthSaml#safe_attr failed for name=#{name}: #{e.message}" if defined?(Legion::Logging)
            nil
          end

          private :register_metadata, :register_login, :register_acs
        end
      end
    end
  end
end
