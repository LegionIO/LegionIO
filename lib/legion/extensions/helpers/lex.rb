# frozen_string_literal: true

require 'legion/json/helper'
require_relative 'secret'

module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Extensions::Helpers::Core
        include Legion::Extensions::Helpers::Logger
        include Legion::JSON::Helper
        include Legion::Extensions::Helpers::Secret

        module ClassMethods
          # @deprecated Use mcp_exposed: flag in definition DSL instead
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

          # @deprecated Use mcp_exposed: flag in definition DSL instead
          def mcp_tool_prefix(value = :_unset)
            if value == :_unset
              @mcp_tool_prefix
            else
              @mcp_tool_prefix = value
            end
          end
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
