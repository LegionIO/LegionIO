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

            @hooks[hook_name.to_sym] = {
              extension:      lex_class.to_s.downcase,
              extension_name: extension_name,
              hook_name:      hook_name,
              hook_class:     hook_class
            }
          end
        end

        def hook_files
          @hook_files ||= find_files('hooks')
        end
      end
    end
  end
end
