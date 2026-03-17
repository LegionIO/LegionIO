# frozen_string_literal: true

module Legion
  module MCP
    module Auth
      module_function

      def authenticate(token)
        return { authenticated: false, error: 'missing_token' } unless token

        if jwt_token?(token)
          verify_jwt(token)
        else
          verify_api_key(token)
        end
      end

      def auth_enabled?
        Legion::Settings.dig(:mcp, :auth, :enabled) == true
      end

      def require_auth?
        Legion::Settings.dig(:mcp, :auth, :require_auth) == true
      end

      def jwt_token?(token)
        token.count('.') == 2
      end

      def verify_jwt(token)
        return { authenticated: false, error: 'crypt_unavailable' } unless defined?(Legion::Crypt::JWT)

        claims = Legion::Crypt::JWT.decode(token)
        { authenticated: true, identity: { user_id: claims[:sub], risk_tier: claims[:risk_tier]&.to_sym,
                                            tenant_id: claims[:tenant_id], worker_id: claims[:worker_id] } }
      rescue StandardError => e
        { authenticated: false, error: e.message }
      end

      def verify_api_key(token)
        allowed = Legion::Settings.dig(:mcp, :auth, :allowed_api_keys) || []
        if allowed.include?(token)
          { authenticated: true, identity: { user_id: 'api_key', risk_tier: :low } }
        else
          { authenticated: false, error: 'invalid_api_key' }
        end
      end
    end
  end
end
