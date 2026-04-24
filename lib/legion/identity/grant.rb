# frozen_string_literal: true

module Legion
  module Identity
    class Grant
      attr_reader :grant_id, :token, :provider, :qualifier, :purpose, :result, :reason, :expires_at

      def initialize(grant_id:, token:, provider:, result:, qualifier: :default, purpose: nil, reason: nil, expires_at: nil) # rubocop:disable Metrics/ParameterLists
        @grant_id   = grant_id
        @token      = token
        @provider   = provider
        @qualifier  = qualifier
        @purpose    = purpose
        @result     = result
        @reason     = reason
        @expires_at = expires_at
        freeze
      end

      def granted? = result == :granted
      def denied?  = result == :denied
    end
  end
end
