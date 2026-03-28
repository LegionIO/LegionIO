# frozen_string_literal: true

module Legion
  module Extensions
    module Definitions
      DEFAULTS = {
        remote_invocable: true,
        mcp_exposed:      true,
        idempotent:       false,
        risk_tier:        :standard,
        tags:             [],
        requires:         [],
        inputs:           {},
        outputs:          {}
      }.freeze

      def definition(method_name, **opts)
        base = DEFAULTS.transform_values do |value|
          case value
          when Array, Hash
            value.dup
          else
            value
          end
        end
        own_definitions[method_name.to_sym] = base.merge(opts)
      end

      def definitions
        if superclass.respond_to?(:definitions)
          superclass.definitions.merge(own_definitions)
        else
          own_definitions.dup
        end
      end

      def definition_for(method_name)
        definitions[method_name.to_sym]
      end

      private

      def own_definitions
        @own_definitions ||= {}
      end
    end
  end
end
