# frozen_string_literal: true

module Legion
  module Identity
    class Lease
      attr_reader :provider, :credential, :lease_id, :expires_at, :renewable, :issued_at, :metadata

      def initialize(provider:, credential:, lease_id: nil, expires_at: nil, renewable: false, issued_at: nil, metadata: {})
        @provider = provider
        @credential = credential
        @lease_id = lease_id
        @expires_at = expires_at
        @renewable = renewable
        @issued_at = issued_at || Time.now
        @metadata = metadata.freeze
      end

      def token
        credential
      end

      def expired?
        return false if expires_at.nil?

        Time.now >= expires_at
      end

      def stale?
        return false if expires_at.nil? || issued_at.nil?

        elapsed = Time.now - issued_at
        total = expires_at - issued_at
        return false if total <= 0

        elapsed >= (total * 0.5)
      end

      def ttl_seconds
        return nil if expires_at.nil?

        remaining = expires_at - Time.now
        remaining.negative? ? 0 : remaining.to_i
      end

      def valid?
        !credential.nil? && !expired?
      end

      def to_h
        {
          provider:   provider,
          lease_id:   lease_id,
          expires_at: expires_at&.iso8601,
          renewable:  renewable,
          issued_at:  issued_at&.iso8601,
          ttl:        ttl_seconds,
          valid:      valid?,
          metadata:   metadata
        }
      end
    end
  end
end
