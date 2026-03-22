# frozen_string_literal: true

module Legion
  module Sandbox
    class Policy
      CAPABILITIES = %w[
        network:outbound network:inbound
        filesystem:read filesystem:write
        llm:invoke llm:embed
        data:read data:write
        cache:read cache:write
        transport:publish transport:subscribe
      ].freeze

      attr_reader :extension_name, :capabilities, :allowed_domains

      def initialize(extension_name:, capabilities: [], allowed_domains: nil)
        @extension_name = extension_name
        @capabilities = capabilities.select { |c| CAPABILITIES.include?(c) }.freeze
        @allowed_domains = allowed_domains&.map(&:to_s)&.freeze
      end

      def allowed?(capability)
        capabilities.include?(capability.to_s)
      end

      def domain_allowed?(agent_domain)
        return true if allowed_domains.nil? || allowed_domains.empty?

        allowed_domains.include?(agent_domain.to_s)
      end
    end

    class << self
      def register_policy(extension_name, capabilities:, allowed_domains: nil)
        policies[extension_name] = Policy.new(
          extension_name:  extension_name,
          capabilities:    capabilities,
          allowed_domains: allowed_domains
        )
      end

      def policy_for(extension_name)
        policies[extension_name] || Policy.new(extension_name: extension_name)
      end

      def enforce!(extension_name, capability)
        return true unless enforcement_enabled?

        policy = policy_for(extension_name)
        raise SecurityError, "Extension #{extension_name} not authorized for: #{capability}" unless policy.allowed?(capability)

        true
      end

      def allowed?(extension_name: nil, gem_name: nil, capability: nil, agent_domain: nil)
        ext = extension_name || gem_name
        return true unless enforcement_enabled?

        policy = policy_for(ext)

        return false if capability && !policy.allowed?(capability)

        return false if agent_domain && !policy.domain_allowed?(agent_domain)

        true
      end

      def enforcement_enabled?
        return false unless defined?(Legion::Settings)

        Legion::Settings.dig(:sandbox, :enabled) != false
      end

      def clear!
        @policies = {}
      end

      private

      def policies
        @policies ||= {}
      end
    end
  end
end
