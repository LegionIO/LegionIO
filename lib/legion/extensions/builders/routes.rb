# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Routes
        include Legion::Extensions::Builder::Base

        attr_reader :routes

        def build_routes
          @routes = {}
          return if lex_route_settings[:enabled] == false
          return if extension_disabled?

          @runners.each_value do |runner_info|
            runner_name   = runner_info[:runner_name]
            runner_class  = runner_info[:runner_class]
            runner_module = runner_info[:runner_module]
            next if runner_module.nil?
            next if excluded_runner?(runner_name)

            methods = runner_module.instance_methods(false)
            methods -= runner_module.skip_routes if runner_module.respond_to?(:skip_routes)
            methods -= excluded_functions_for

            methods.each do |function|
              route_path = "#{extension_name}/#{runner_name}/#{function}"
              Legion::Logging.info "[Routes] auto-route registered: POST /api/lex/#{route_path}" if defined?(Legion::Logging)
              @routes[route_path] = {
                lex_name:     extension_name,
                runner_name:  runner_name,
                function:     function,
                runner_class: runner_class,
                route_path:   route_path
              }
            end
          end
        end

        private

        def lex_route_settings
          return {} unless defined?(Legion::Settings)

          Legion::Settings.dig(:api, :lex_routes) || {}
        end

        def extension_disabled?
          lex_route_settings.dig(:extensions, extension_name.to_sym, :enabled) == false
        end

        def excluded_runner?(runner_name)
          runners_list = Array(lex_route_settings.dig(:extensions, extension_name.to_sym, :exclude_runners))
          runners_list.include?(runner_name)
        end

        def excluded_functions_for
          functions_list = Array(lex_route_settings.dig(:extensions, extension_name.to_sym, :exclude_functions))
          functions_list.select { |f| f.is_a?(String) || f.is_a?(Symbol) }.map(&:to_sym)
        end
      end
    end
  end
end
