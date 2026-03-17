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

      attr_reader :extension_name, :capabilities

      def initialize(extension_name:, capabilities: [])
        @extension_name = extension_name
        @capabilities = capabilities.select { |c| CAPABILITIES.include?(c) }.freeze
      end

      def allowed?(capability)
        capabilities.include?(capability.to_s)
      end
    end

    class << self
      def register_policy(extension_name, capabilities:)
        policies[extension_name] = Policy.new(
          extension_name: extension_name,
          capabilities:   capabilities
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
