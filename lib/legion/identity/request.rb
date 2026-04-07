# frozen_string_literal: true

module Legion
  module Identity
    class Request
      # Maps middleware-emitted source values to the canonical credential enum.
      # :local is emitted by Middleware#system_principal for unauthenticated loopback
      # requests and must normalize to :system to maintain audit trail consistency.
      # :jwt is intentionally kept distinct — JWT is the transport, not the provider.
      # Entra-specific identification requires issuer inspection (Phase 7 concern).
      SOURCE_NORMALIZATION = {
        api_key:  :api,
        jwt:      :jwt,
        kerberos: :kerberos,
        local:    :system,
        system:   :system
      }.freeze

      attr_reader :principal_id, :canonical_name, :kind, :groups, :source, :metadata

      def initialize(principal_id:, canonical_name:, kind:, groups: [], source: nil, metadata: {}) # rubocop:disable Metrics/ParameterLists
        @principal_id   = principal_id
        @canonical_name = canonical_name
        @kind           = kind
        @groups         = groups.freeze
        @source         = source
        @metadata       = metadata.freeze
        freeze
      end

      # Reads the already-resolved identity from the Rack env (set by middleware).
      # Returns nil when the key is absent.
      def self.from_env(env)
        env['legion.principal']
      end

      # Builds a Request from a parsed auth claims hash with symbol keys:
      #   { sub:, name:, preferred_username:, kind:, groups:, source: }
      # The source value is normalized via SOURCE_NORMALIZATION at construction time.
      def self.from_auth_context(claims_hash)
        raw_name = claims_hash[:name] || claims_hash[:preferred_username] || ''
        canonical = raw_name.to_s.strip.downcase.gsub('.', '-')
        raw_source = claims_hash[:source]&.to_sym
        normalized_source = SOURCE_NORMALIZATION.fetch(raw_source, raw_source)

        new(
          principal_id:   claims_hash[:sub],
          canonical_name: canonical,
          kind:           claims_hash[:kind] || :human,
          groups:         claims_hash[:groups] || [],
          source:         normalized_source
        )
      end

      def identity_hash
        {
          principal_id:   principal_id,
          canonical_name: canonical_name,
          kind:           kind,
          groups:         groups,
          source:         source
        }
      end

      # Maps to RBAC principal format.
      # :service workers are represented as :worker in RBAC.
      def to_rbac_principal
        {
          identity: canonical_name,
          type:     kind == :service ? :worker : kind
        }
      end

      # Pipeline-compatible caller hash (matches legion-llm pipeline format).
      def to_caller_hash
        {
          requested_by: {
            id:         principal_id,
            identity:   canonical_name,
            type:       kind,
            credential: source
          }
        }
      end
    end
  end
end
