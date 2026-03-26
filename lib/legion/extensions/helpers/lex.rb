# frozen_string_literal: true

require 'legion/json/helper'

module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Extensions::Helpers::Core
        include Legion::Extensions::Helpers::Logger
        include Legion::JSON::Helper

        module ClassMethods
          def expose_as_mcp_tool(value = :_unset)
            if value == :_unset
              return @expose_as_mcp_tool unless @expose_as_mcp_tool.nil?

              if defined?(Legion::Settings) && Legion::Settings.respond_to?(:dig)
                Legion::Settings.dig(:mcp, :auto_expose_runners) || false
              else
                false
              end
            else
              @expose_as_mcp_tool = value
            end
          end

          def mcp_tool_prefix(value = :_unset)
            if value == :_unset
              @mcp_tool_prefix
            else
              @mcp_tool_prefix = value
            end
          end
        end

        def function_example(function, example)
          function_set(function, :example, example)
        end

        def function_options(function, options)
          function_set(function, :options, options)
        end

        def function_desc(function, desc)
          function_set(function, :desc, desc)
        end

        def function_outputs(function, outputs)
          function_set(function, :outputs, outputs)
        end

        def function_category(function, category)
          function_set(function, :category, category)
        end

        def function_tags(function, tags)
          function_set(function, :tags, tags)
        end

        def function_risk_tier(function, tier)
          function_set(function, :risk_tier, tier)
        end

        def function_idempotent(function, value)
          function_set(function, :idempotent, value)
        end

        def function_requires(function, deps)
          function_set(function, :requires, deps)
        end

        def function_expose(function, value)
          function_set(function, :expose, value)
        end

        def function_set(function, key, value)
          unless respond_to? function
            log.debug "function_#{key} called but function doesn't exist, f: #{function}"
            return nil
          end
          settings[:functions] = {} if settings[:functions].nil?
          settings[:functions][function] = {} if settings[:functions][function].nil?
          settings[:functions][function][key] = value
        end

        def runner_desc(desc)
          settings[:runners] = {} if settings[:runners].nil?
          settings[:runners][actor_name.to_sym] = {} if settings[:runners][actor_name.to_sym].nil?
          settings[:runners][actor_name.to_sym][:desc] = desc
        end

        def self.included(base)
          base.send :extend, Legion::Extensions::Helpers::Core if base.instance_of?(Class)
          base.send :extend, Legion::Extensions::Helpers::Logger if base.instance_of?(Class)
          base.extend ClassMethods if base.instance_of?(Class)
          base.extend base if base.instance_of?(Module)
        end

        def default_settings
          { logger: { level: 'info' }, workers: 1, runners: {}, functions: {} }
        end
      end
    end
  end
end
