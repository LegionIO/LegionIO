# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Hooks
        include Legion::Extensions::Builder::Base

        attr_reader :hooks

        def build_hooks
          @hooks = {}
          return unless Dir.exist? "#{extension_path}/hooks"

          require_files(hook_files)
          build_hook_list
        end

        def build_hook_list
          hook_files.each do |file|
            hook_name = file.split('/').last.sub('.rb', '')
            hook_class_name = "#{lex_class}::Hooks::#{hook_name.split('_').collect(&:capitalize).join}"

            next unless Kernel.const_defined?(hook_class_name)

            hook_class = Kernel.const_get(hook_class_name)
            next unless hook_class < Legion::Extensions::Hooks::Base

            route_path = "#{extension_name}/#{hook_name}"
            runner = hook_class.respond_to?(:runner_class) ? hook_class.runner_class : nil

            @hooks[hook_name.to_sym] = {
              extension:      lex_class.to_s.downcase,
              extension_name: extension_name,
              hook_name:      hook_name,
              hook_class:     hook_class,
              route_path:     route_path
            }

            next unless defined?(Legion::API) && Legion::API.respond_to?(:router)

            # Register hook component in the router (explicit methods derived from hook class)
            hook_methods = hook_class.public_instance_methods(false).reject { |m| m.to_s.start_with?('_') }
            hook_methods = [:handle] if hook_methods.empty?
            hook_methods.each do |method_name|
              Legion::API.router.register_extension_route(
                lex_name:       extension_name,
                component_type: 'hooks',
                component_name: hook_name,
                method_name:    method_name.to_s,
                runner_class:   runner || hook_class,
                definition:     hook_class.respond_to?(:definition_for) ? hook_class.definition_for(method_name) : nil
              )
            end
          end
        end

        def hook_files
          @hook_files ||= find_files('hooks')
        end
      end
    end
  end
end
