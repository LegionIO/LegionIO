# frozen_string_literal: true

require 'time'

module Legion
  module Auth
    class TokenManager
      class TokenExpiredError < StandardError
      end

      def initialize(provider:)
        @provider = provider
      end

      def token_valid?
        access_token = secret[:"#{@provider}_access_token"]
        return false unless access_token

        expires_at_str = secret[:"#{@provider}_token_expires_at"]
        return false unless expires_at_str

        expires_at = Time.parse(expires_at_str)
        ttl = secret[:"#{@provider}_token_ttl"]

        expires_at > if ttl
                       Time.now + (ttl * 0.25)
                     else
                       Time.now + 300
                     end
      end

      def store_tokens(access_token:, expires_in:, refresh_token: nil, scope: nil)
        secret[:"#{@provider}_access_token"]     = access_token
        secret[:"#{@provider}_refresh_token"]    = refresh_token if refresh_token
        secret[:"#{@provider}_token_ttl"]        = expires_in
        secret[:"#{@provider}_token_scope"]      = scope if scope
        secret[:"#{@provider}_token_expires_at"] = (Time.now + expires_in).iso8601
      end

      def ensure_valid_token
        return secret[:"#{@provider}_access_token"] if token_valid?

        refresh_access_token
      end

      def revoked?
        secret[:"#{@provider}_token_revoked"] == true
      end

      def mark_revoked!
        secret[:"#{@provider}_token_revoked"] = true
      end

      private

      def secret
        @secret ||= begin
          if defined?(Legion::Extensions::Helpers::SecretAccessor)
            Legion::Extensions::Helpers::SecretAccessor.new(lex_name: 'auth')
          else
            {}
          end
        rescue StandardError
          {}
        end
      end

      def refresh_access_token
        # Will be implemented when OAuth2 callback server is wired in Task 2.2
        nil
      end
    end
  end
end
