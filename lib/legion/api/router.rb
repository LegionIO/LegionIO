# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    class Router
      def initialize
        @infrastructure_routes = []
        @library_routes = {}
        @extension_routes = {}
      end

      # --- Infrastructure tier ---

      def register_infrastructure(path, method: :get, summary: nil)
        @infrastructure_routes << { path: path, method: method, summary: summary }
      end

      def infrastructure_routes
        @infrastructure_routes.dup
      end

      # --- Library gem tier ---

      def register_library(gem_name, routes_module)
        @library_routes[gem_name.to_s] = routes_module
      end

      def library_routes
        @library_routes.dup
      end

      def library_names
        @library_routes.keys
      end

      # --- Extension tier ---

      def register_extension_route(**opts)
        lex_name = opts[:lex_name]
        component_type = opts[:component_type]
        component_name = opts[:component_name]
        method_name = opts[:method_name]
        key = "#{lex_name}/#{component_type}/#{component_name}/#{method_name}"
        @extension_routes[key] = {
          lex_name:       lex_name.to_s,
          component_type: component_type.to_s,
          component_name: component_name.to_s,
          method_name:    method_name.to_s,
          runner_class:   opts[:runner_class],
          definition:     opts[:definition]
        }
      end

      def find_extension_route(lex_name, component_type, component_name, method_name)
        key = "#{lex_name}/#{component_type}/#{component_name}/#{method_name}"
        @extension_routes[key]
      end

      def extension_routes
        @extension_routes.dup
      end

      def extension_names
        @extension_routes.values.map { |r| r[:lex_name] }.uniq
      end

      def components_for(lex_name)
        @extension_routes.values
                         .select { |r| r[:lex_name] == lex_name.to_s }
                         .group_by { |r| r[:component_type] }
      end

      def methods_for(lex_name, component_type, component_name)
        @extension_routes.values.select do |r|
          r[:lex_name] == lex_name.to_s &&
            r[:component_type] == component_type.to_s &&
            r[:component_name] == component_name.to_s
        end
      end

      def discovery_extension(lex_name)
        comps = components_for(lex_name)
        return nil if comps.empty?

        comps.transform_values do |routes|
          routes.map { |r| { name: r[:component_name], method: r[:method_name], definition: r[:definition] } }
        end
      end

      def clear!
        @infrastructure_routes.clear
        @library_routes.clear
        @extension_routes.clear
      end
    end
  end
end
