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
              defn = runner_module.respond_to?(:definition_for) ? runner_module.definition_for(function) : nil
              log.info "[Routes] auto-route registered: POST /api/extensions/#{extension_name}/runners/#{runner_name}/#{function}"
              @routes[route_path] = {
                lex_name:       extension_name,
                runner_name:    runner_name,
                function:       function,
                component_type: 'runners',
                runner_class:   runner_class,
                route_path:     route_path,
                definition:     defn
              }

              next unless defined?(Legion::API) && Legion::API.respond_to?(:router)

              Legion::API.router.register_extension_route(
                lex_name:       extension_name,
                amqp_prefix:    respond_to?(:amqp_prefix) ? amqp_prefix : "lex.#{extension_name.to_s.tr('_', '.')}",
                component_type: 'runners',
                component_name: runner_name,
                method_name:    function.to_s,
                runner_class:   runner_class,
                definition:     defn
              )
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
