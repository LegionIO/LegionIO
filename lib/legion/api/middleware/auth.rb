# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Middleware
      class Auth
        SKIP_PATHS      = %w[/api/health /api/ready /api/openapi.json /metrics /api/auth/token /api/auth/worker-token].freeze
        AUTH_HEADER     = 'HTTP_AUTHORIZATION'
        BEARER_PATTERN  = /\ABearer\s+(.+)\z/i
        API_KEY_HEADER  = 'HTTP_X_API_KEY'

        def initialize(app, opts = {})
          @app        = app
          @enabled    = opts.fetch(:enabled, false)
          @signing_key = opts[:signing_key]
          @api_keys = opts.fetch(:api_keys, {})
        end

        def call(env)
          return @app.call(env) unless @enabled
          return @app.call(env) if skip_path?(env['PATH_INFO'])

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
            return unauthorized('invalid API key')
          end

          unauthorized('missing Authorization header')
        end

        private

        def skip_path?(path)
          SKIP_PATHS.any? { |p| path.start_with?(p) }
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
