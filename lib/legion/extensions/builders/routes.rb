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

          disabled_exts = Array(lex_route_settings[:disabled_extensions])
          return if disabled_exts.include?(extension_name)

          @runners.each_value do |runner_info|
            runner_name   = runner_info[:runner_name]
            runner_class  = runner_info[:runner_class]
            runner_module = runner_info[:runner_module]
            next if runner_module.nil?
            next if excluded_runner?(runner_name)

            methods = runner_module.instance_methods(false)
            methods -= runner_module.skip_routes if runner_module.respond_to?(:skip_routes)
            methods -= excluded_functions_for(runner_name)

            methods.each do |function|
              route_path = "#{extension_name}/#{runner_name}/#{function}"
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

        def excluded_runner?(runner_name)
          runners_list = Array(lex_route_settings[:exclude_runners])
          runners_list.include?("#{extension_name}/#{runner_name}")
        end

        def excluded_functions_for(runner_name)
          functions_list = Array(lex_route_settings[:exclude_functions])
          functions_list.filter_map do |path|
            parts = path.split('/')
            next unless parts.length == 3 && parts[0] == extension_name && parts[1] == runner_name

            parts[2].to_sym
          end
        end
      end
    end
  end
end
