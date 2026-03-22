# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Middleware
      class Auth
        SKIP_PATHS       = %w[/api/health /api/ready /api/openapi.json /metrics /api/auth/token /api/auth/worker-token
                              /api/auth/authorize /api/auth/callback /api/auth/negotiate].freeze
        AUTH_HEADER      = 'HTTP_AUTHORIZATION'
        BEARER_PATTERN   = /\ABearer\s+(.+)\z/i
        NEGOTIATE_PATTERN = /\ANegotiate\s+(.+)\z/i
        API_KEY_HEADER = 'HTTP_X_API_KEY'

        def initialize(app, opts = {})
          @app        = app
          @enabled    = opts.fetch(:enabled, false)
          @signing_key = opts[:signing_key]
          @api_keys = opts.fetch(:api_keys, {})
        end

        def call(env)
          return @app.call(env) unless @enabled
          return @app.call(env) if skip_path?(env['PATH_INFO'])

          # Try Negotiate/SPNEGO first (Kerberos)
          result = try_negotiate(env)
          return result if result

          # Try Bearer JWT first
          token = extract_token(env)
          if token
            claims = verify_token(token)
            if claims
              env['legion.auth']        = claims
              env['legion.auth_method'] = 'jwt'
              env['legion.worker_id']   = claims[:worker_id]
              env['legion.owner_msid']  = claims[:sub] || claims[:owner_msid]
              return @app.call(env)
            end
            Legion::Logging.warn "API auth failure: invalid or expired JWT token for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}" if defined?(Legion::Logging)
            return unauthorized('invalid or expired token')
          end

          # Try API key
          api_key = extract_api_key(env)
          if api_key
            key_meta = verify_api_key(api_key)
            if key_meta
              env['legion.auth']        = key_meta
              env['legion.auth_method'] = 'api_key'
              env['legion.worker_id']   = key_meta[:worker_id]
              env['legion.owner_msid']  = key_meta[:owner_msid]
              return @app.call(env)
            end
            Legion::Logging.warn "API auth failure: invalid API key for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}" if defined?(Legion::Logging)
            return unauthorized('invalid API key')
          end

          Legion::Logging.warn "API auth failure: missing Authorization header for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}" if defined?(Legion::Logging)
          unauthorized('missing Authorization header')
        end

        private

        def try_negotiate(env)
          negotiate_token = extract_negotiate_token(env)
          return nil unless negotiate_token

          negotiate_result = verify_negotiate(negotiate_token)
          unless negotiate_result
            return kerberos_available? ? unauthorized('Kerberos authentication failed') : nil
          end

          env['legion.auth']        = negotiate_result[:claims]
          env['legion.auth_method'] = 'kerberos'
          env['legion.owner_msid']  = negotiate_result[:claims][:sub]
          status, app_headers, body = @app.call(env)
          response_headers = app_headers.dup
          response_headers['WWW-Authenticate'] = "Negotiate #{negotiate_result[:output_token]}" if negotiate_result[:output_token]
          [status, response_headers, body]
        end

        def skip_path?(path)
          SKIP_PATHS.any? { |p| path.start_with?(p) }
        end

        def extract_negotiate_token(env)
          header = env[AUTH_HEADER]
          return nil unless header

          match = header.match(NEGOTIATE_PATTERN)
          match&.captures&.first
        end

        def verify_negotiate(token)
          return nil unless kerberos_available?

          client = Legion::Extensions::Kerberos::Client.new
          auth_result = client.authenticate(token: token)
          return nil unless auth_result[:success]

          claims = Legion::Rbac::KerberosClaimsMapper.map_with_fallback(
            principal: auth_result[:principal],
            groups:    auth_result[:groups] || [],
            role_map:  kerberos_role_map,
            fallback:  kerberos_fallback
          )

          { claims: claims, output_token: auth_result[:output_token] }
        rescue StandardError
          nil
        end

        def kerberos_available?
          defined?(Legion::Extensions::Kerberos::Client) &&
            defined?(Legion::Rbac::KerberosClaimsMapper)
        end

        def kerberos_role_map
          return {} unless defined?(Legion::Settings)

          Legion::Settings.dig(:kerberos, :role_map) || {}
        rescue StandardError
          {}
        end

        def kerberos_fallback
          return :entra unless defined?(Legion::Settings)

          Legion::Settings.dig(:kerberos, :fallback) || :entra
        rescue StandardError
          :entra
        end

        def extract_api_key(env)
          env[API_KEY_HEADER]
        end

        def verify_api_key(key)
          return nil unless @api_keys.is_a?(Hash)

          @api_keys[key]
        end

        def extract_token(env)
          header = env[AUTH_HEADER]
          return nil unless header

          match = header.match(BEARER_PATTERN)
          match&.captures&.first
        end

        def verify_token(token)
          key = @signing_key || default_signing_key
          return nil unless key

          Legion::Crypt::JWT.verify(token, verification_key: key)
        rescue Legion::Crypt::JWT::Error
          nil
        end

        def default_signing_key
          return Legion::Crypt.cluster_secret if defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:cluster_secret)

          nil
        end

        def unauthorized(message)
          body = Legion::JSON.dump({ error: { code: 401, message: message }, meta: { timestamp: Time.now.utc.iso8601 } })
          [401, { 'content-type' => 'application/json' }, [body]]
        rescue StandardError
          [401, { 'content-type' => 'application/json' }, ["{\"error\":{\"code\":401,\"message\":\"#{message}\"}}"]]
        end
      end
    end
  end
end
