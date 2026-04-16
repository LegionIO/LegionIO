# frozen_string_literal: true

module Legion
  module Tools
    module Discovery
      # Extension/runner pairs that should always be loaded (not deferred)
      # nil means all runners for that extension; array means specific runners only
      ALWAYS_LOADED = {
        'apollo' => ['knowledge'],
        'eval'   => ['evaluation']
      }.freeze

      class << self
        def log
          Legion::Logging.respond_to?(:logger) ? Legion::Logging.logger : nil
        end

        def handle_exception(err, **opts)
          log&.warn("[Tools::Discovery] #{opts[:operation]}: #{err.message}")
        end

        def discover_and_register
          return unless defined?(Legion::Extensions)

          exts = loaded_extensions
          log&.info("[Tools::Discovery] scanning #{exts.size} extensions")

          exts.each do |ext|
            discover_runners(ext)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: :discovery_process_extension)
          end

          log&.info(
            "[Tools::Discovery] done: always=#{Registry.tools.size} " \
            "deferred=#{Registry.deferred_tools.size}"
          )
        end

        private

        def loaded_extensions
          if Legion::Extensions.respond_to?(:loaded_extension_modules)
            Legion::Extensions.loaded_extension_modules || []
          else
            Legion::Extensions.constants(false).filter_map do |const_name|
              mod = Legion::Extensions.const_get(const_name, false)
              next nil unless mod.is_a?(Module) && mod.respond_to?(:runner_modules)

              mod
            rescue StandardError => e
              handle_exception(e, level: :warn, handled: true, operation: :discovery_loaded_extensions)
              nil
            end
          end
        end

        def discover_runners(ext)
          return unless ext.respond_to?(:runner_modules)

          ext.runner_modules.each do |runner_mod|
            next unless runner_mod.respond_to?(:settings) && runner_mod.settings.is_a?(Hash)
            next unless resolve_mcp_tools_enabled(ext, runner_mod)

            functions = runner_mod.settings[:functions]
            functions = synthesize_functions(ext, runner_mod) if functions.nil? || functions.empty?
            next if functions.nil? || functions.empty?

            is_deferred = resolve_deferred(ext, runner_mod)
            functions.each do |func_name, meta|
              register_function(ext, runner_mod, func_name, meta, is_deferred)
            end
          end
        end

        def synthesize_functions(ext, runner_mod)
          return {} unless ext.respond_to?(:runners) && ext.runners.is_a?(Hash)

          runner_entry = ext.runners.values.find { |r| r[:runner_module] == runner_mod }
          return {} unless runner_entry&.dig(:class_methods).is_a?(Hash)

          runner_entry[:class_methods].each_with_object({}) do |(method_name, method_info), funcs|
            defn = runner_mod.respond_to?(:definition_for) ? runner_mod.definition_for(method_name) : nil
            funcs[method_name] = {
              desc:    defn&.dig(:desc) || method_name.to_s,
              options: build_schema_from_args(method_info[:args]),
              args:    method_info[:args]
            }
          end
        end

        def build_schema_from_args(args)
          return {} if args.nil? || args.empty?

          properties = {}
          required = []

          args.each do |type, name|
            next if name.nil? || %i[** * block].include?(name)

            param_name = name.to_s
            properties[param_name] = { type: 'string' }
            required << param_name if type == :req
          end

          return {} if properties.empty?

          schema = { properties: properties }
          schema[:required] = required unless required.empty?
          schema
        end

        def register_function(ext, runner_mod, func_name, meta, is_deferred)
          defn = runner_mod.respond_to?(:definition_for) ? runner_mod.definition_for(func_name) : nil

          ext_default = ext.respond_to?(:mcp_tools?) ? ext.mcp_tools? : true
          return unless resolve_exposed(defn, meta, ext_default)

          requires = defn&.dig(:requires)&.map(&:to_s) || meta[:requires]
          return unless deps_satisfied?(requires)

          tool_class = build_tool_class(
            ext: ext, runner_mod: runner_mod, func_name: func_name,
            meta: meta, defn: defn, deferred: is_deferred
          )
          Legion::Tools::Registry.register(tool_class)
        end

        def resolve_mcp_tools_enabled(ext, runner_mod)
          return runner_mod.mcp_tools? if runner_mod.respond_to?(:mcp_tools?)

          ext.respond_to?(:mcp_tools?) ? ext.mcp_tools? : true
        end

        def resolve_deferred(ext, runner_mod)
          ext_name = derive_extension_name(ext)
          runner_name = derive_runner_snake(runner_mod)
          if ALWAYS_LOADED.key?(ext_name)
            runners = ALWAYS_LOADED[ext_name]
            return false if runners.nil? || runners.include?(runner_name)
          end

          return runner_mod.mcp_tools_deferred? if runner_mod.respond_to?(:mcp_tools_deferred?)

          ext.respond_to?(:mcp_tools_deferred?) ? ext.mcp_tools_deferred? : true
        end

        def resolve_exposed(defn, meta, ext_default)
          return defn[:mcp_exposed] unless defn.nil? || defn[:mcp_exposed].nil?
          return meta[:expose] unless meta[:expose].nil?

          ext_default
        end

        def deps_satisfied?(deps)
          return true if deps.nil? || deps.empty?

          deps.all? do |dep|
            parts = dep.delete_prefix('::').split('::').reject(&:empty?)
            current = Object
            parts.all? do |part|
              current.const_defined?(part, false) ? (current = current.const_get(part, false)) && true : false
            end
          end
        end

        def build_tool_class(ext:, runner_mod:, func_name:, meta:, defn:, deferred:) # rubocop:disable Metrics/ParameterLists
          attrs = tool_attributes(ext, runner_mod, func_name, meta, defn, deferred)
          create_tool_class(attrs, runner_mod, func_name)
        end

        def tool_attributes(ext, runner_mod, func_name, meta, defn, deferred) # rubocop:disable Metrics/ParameterLists
          ext_name = derive_extension_name(ext)
          runner_snake = derive_runner_snake(runner_mod)
          {
            tool_name:     defn&.dig(:mcp_prefix) || "legion-#{ext_name}-#{runner_snake}-#{func_name}",
            description:   meta[:desc] || defn&.dig(:desc) || "#{ext_name}##{func_name}",
            input_schema:  normalize_schema(defn&.dig(:inputs)&.any? ? defn[:inputs] : meta[:options]),
            mcp_category:  defn&.dig(:mcp_category),
            mcp_tier:      defn&.dig(:mcp_tier),
            deferred:      deferred,
            ext_name:      ext_name,
            runner_snake:  runner_snake,
            trigger_words: merge_trigger_words(ext, runner_mod),
            sticky:        ext.respond_to?(:sticky_tools?) ? ext.sticky_tools? == true : true
          }
        end

        def create_tool_class(attrs, runner_ref, func_ref)
          Class.new(Legion::Tools::Base) do
            tool_name attrs[:tool_name]
            description attrs[:description]
            input_schema(attrs[:input_schema])
            deferred(attrs[:deferred])
            extension(attrs[:ext_name])
            runner(attrs[:runner_snake])
            mcp_category(attrs[:mcp_category]) if attrs[:mcp_category]
            mcp_tier(attrs[:mcp_tier]) if attrs[:mcp_tier]
            trigger_words(attrs[:trigger_words])
            sticky(attrs[:sticky])

            define_singleton_method(:call) do |**params|
              if runner_ref.respond_to?(func_ref)
                result = runner_ref.public_send(func_ref, **params)
                text = result.is_a?(String) ? result : Legion::JSON.dump(result)
                text_response(text)
              else
                error_response("function #{func_ref} not found on #{runner_ref}")
              end
            rescue StandardError => e
              handle_exception(e, level: :warn, handled: true, operation: :"discovery_call_#{func_ref}")
              error_response(e.message)
            end
          end
        end

        def merge_trigger_words(ext, runner_mod)
          ext_words = ext.respond_to?(:trigger_words) ? Array(ext.trigger_words) : []

          # Prefer explicit trigger_words on the runner module itself.
          # Fall back to the runner entry stored by builders/runners.rb, which
          # defaults to [runner_name] when the module doesn't define them.
          runner_words = if runner_mod.respond_to?(:trigger_words) && runner_mod.trigger_words.any?
                           Array(runner_mod.trigger_words)
                         elsif ext.respond_to?(:runners) && ext.runners.is_a?(Hash)
                           entry = ext.runners.values.find { |r| r[:runner_module] == runner_mod }
                           Array(entry&.dig(:trigger_words))
                         else
                           []
                         end

          (ext_words + runner_words).uniq
        end

        def derive_runner_snake(runner_mod)
          mod_name = runner_mod.name
          return 'unknown' unless mod_name

          last = mod_name.split('::').last
          last.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
        end

        def normalize_schema(schema)
          schema = { properties: {} } if schema.nil? || schema.empty?
          schema = schema.dup
          schema[:type] ||= 'object'
          schema[:properties] ||= {}
          schema
        end

        def derive_extension_name(ext)
          if ext.respond_to?(:lex_name)
            ext.lex_name.delete_prefix('lex-').tr('-', '_')
          else
            mod_name = ext.name
            return 'unknown' unless mod_name

            last = mod_name.split('::').last
            last.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
          end
        end
      end
    end
  end
end
