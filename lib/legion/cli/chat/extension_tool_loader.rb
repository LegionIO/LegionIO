# frozen_string_literal: true

require 'legion/cli/chat/extension_tool'

module Legion
  module CLI
    class Chat
      module ExtensionToolLoader
        TIER_ORDER = { read: 0, write: 1, shell: 2 }.freeze

        class << self
          def discover
            @discover ||= load_all_extension_tools
          end

          def reset!
            @discover = nil
          end

          def tools_dir_for(extension_path)
            "#{extension_path}/tools"
          end

          def collect_tool_classes(tools_module)
            tools_module.constants.filter_map do |const_name|
              klass = tools_module.const_get(const_name)
              klass if klass.is_a?(Class) && klass < RubyLLM::Tool
            end
          end

          def tool_enabled?(extension_name)
            settings = extension_settings(extension_name)
            return true unless settings&.dig(:tools, :enabled) == false

            false
          end

          def effective_tier(tool_class, extension_name)
            class_tier = if tool_class.respond_to?(:declared_permission_tier)
                           tool_class.declared_permission_tier
                         else
                           :write
                         end
            override = settings_tier_for(tool_class, extension_name)
            return class_tier unless override

            TIER_ORDER[override] > TIER_ORDER[class_tier] ? override : class_tier
          end

          def extension_settings(extension_name)
            return nil unless defined?(Legion::Settings)

            Legion::Settings[:extensions]&.[](extension_name.to_sym)
          rescue StandardError
            nil
          end

          private

          def load_all_extension_tools
            tools = []
            loaded_extension_paths.each do |ext_name, ext_path|
              next unless tool_enabled?(ext_name)

              tools_dir = tools_dir_for(ext_path)
              next unless Dir.exist?(tools_dir)

              require_tool_files(tools_dir)
              tools_module = resolve_tools_module(ext_name)
              next unless tools_module

              found = collect_tool_classes(tools_module)
              tools.concat(found)
            end
            tools
          end

          def loaded_extension_paths
            return [] unless defined?(Legion::Extensions)

            Legion::Extensions.instance_variable_get(:@extensions)&.map do |name, info|
              gem_spec = Gem::Specification.find_by_name(info[:gem_name])
              ext_path = "#{gem_spec.gem_dir}/lib/legion/extensions/#{name}"
              [name, ext_path]
            rescue Gem::MissingSpecError
              nil
            end&.compact || []
          end

          def require_tool_files(tools_dir)
            Dir["#{tools_dir}/*.rb"].each { |f| require f }
          end

          def resolve_tools_module(ext_name)
            class_name = ext_name.to_s.split('_').map(&:capitalize).join
            module_path = "Legion::Extensions::#{class_name}::Tools"
            Kernel.const_get(module_path)
          rescue NameError
            nil
          end

          def settings_tier_for(tool_class, extension_name)
            settings = extension_settings(extension_name)
            return nil unless settings

            tool_name = tool_class.name&.split('::')&.last
            return nil unless tool_name

            tool_key = tool_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
            tier = settings.dig(:tools, tool_key, :tier)
            tier&.to_sym
          end
        end
      end
    end
  end
end
