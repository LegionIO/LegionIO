# frozen_string_literal: true

require_relative 'absorbers'
require_relative 'builders/absorbers'
require_relative 'builders/actors'
require_relative 'builders/helpers'
require_relative 'builders/hooks'
require_relative 'builders/routes'
require_relative 'builders/runners'

require_relative 'helpers/segments'
require_relative 'helpers/core'
require_relative 'helpers/task'
require_relative 'helpers/logger'
require_relative 'helpers/lex'
require_relative 'helpers/transport'
require_relative 'helpers/data'
require_relative 'helpers/cache'

begin
  require 'legion/llm/helpers/llm'
rescue LoadError => e
  Legion::Logging.debug "Extensions::Core: legion-llm helpers not available: #{e.message}" if defined?(Legion::Logging)
end

begin
  require_relative 'helpers/llm'
rescue LoadError => e
  Legion::Logging.debug "Extensions::Core: local llm helper not available: #{e.message}" if defined?(Legion::Logging)
end

begin
  require_relative 'helpers/knowledge'
rescue LoadError => e
  Legion::Logging.debug "Extensions::Core: knowledge helper not available: #{e.message}" if defined?(Legion::Logging)
end

require_relative 'actors/base'
require_relative 'actors/every'
require_relative 'actors/loop'
require_relative 'actors/once'
require_relative 'actors/poll'
require_relative 'actors/subscription'
require_relative 'actors/nothing'
require_relative 'hooks/base'

module Legion
  module Extensions
    module Core
      include Legion::Extensions::Helpers::Transport
      include Legion::Extensions::Helpers::Lex
      include Legion::Extensions::Helpers::Knowledge if defined?(Legion::Extensions::Helpers::Knowledge)

      include Legion::Extensions::Builder::Absorbers
      include Legion::Extensions::Builder::Runners
      include Legion::Extensions::Builder::Helpers
      include Legion::Extensions::Builder::Actors
      include Legion::Extensions::Builder::Hooks
      include Legion::Extensions::Builder::Routes

      def autobuild
        Legion::Logging.debug "[Core] autobuild start: #{name}" if defined?(Legion::Logging)
        @actors = {}
        @meta_actors = {}
        @runners = {}
        @helpers = []

        @queues = {}
        @exchanges = {}
        @messages = {}
        build_settings
        build_transport
        if Legion::Settings[:data][:connected] && data_required?
          Legion::Logging.debug "[Core] building data for #{name}" if defined?(Legion::Logging)
          build_data
        end
        build_helpers
        build_runners
        generate_messages_from_definitions
        build_absorbers
        build_actors
        build_hooks
        build_routes
        register_hooks
        register_routes
        Legion::Logging.debug "[Core] autobuild complete: #{name}" if defined?(Legion::Logging)
      end

      def data_required?
        false
      end

      def transport_required?
        true
      end

      def cache_required?
        false
      end

      def crypt_required?
        false
      end

      def vault_required?
        false
      end

      def llm_required?
        false
      end

      def remote_invocable?
        true
      end

      # Auto-generate AMQP message classes for each runner method that has a definition.
      # Explicit Messages::* classes in the transport directory take precedence.
      # Runs after build_runners so definitions are populated.
      def generate_messages_from_definitions
        ctx = message_generation_context
        return unless ctx

        @runners.each do |runner_name, attr|
          generate_runner_messages(ctx, runner_name, attr)
        end
      rescue StandardError => e
        log.warn "[Core] generate_messages_from_definitions failed: #{e.message}" if defined?(log)
      end

      def message_generation_context
        return unless defined?(Legion::Transport::Message)
        return unless lex_class.const_defined?('Transport', false)

        transport_mod = lex_class::Transport
        return unless transport_mod.const_defined?('Messages', false) && transport_mod.const_defined?('Exchanges', false)

        default_exch = transport_mod.default_exchange
        { messages_mod: transport_mod::Messages, default_exch: default_exch, prefix: amqp_prefix }
      rescue StandardError
        nil
      end

      def generate_runner_messages(ctx, runner_name, attr)
        runner_module = attr[:runner_module]
        return unless runner_module.respond_to?(:definitions)

        runner_module.definitions.each_key do |method_name|
          const_name = "#{camelize(runner_name)}#{camelize(method_name)}"
          next if ctx[:messages_mod].const_defined?(const_name, false)

          rk_value = "#{ctx[:prefix]}.runners.#{runner_name}.#{method_name}"
          ctx[:messages_mod].const_set(const_name, Class.new(Legion::Transport::Message) do
            define_method(:exchange) { ctx[:default_exch] }
            define_method(:routing_key) { rk_value }
          end)
        end
      rescue StandardError => e
        log.warn "[Core] message generation error for #{runner_name}: #{e.message}" if defined?(log)
      end

      def camelize(name)
        name.to_s.split('_').collect(&:capitalize).join
      end

      def build_data
        Legion::Logging.debug "[Core] build_data: #{name}" if defined?(Legion::Logging)
        auto_generate_data
        lex_class::Data.build
        Legion::Logging.info "[Core] data built: #{name}" if defined?(Legion::Logging)
      end

      def build_transport
        if File.exist? "#{extension_path}/transport/autobuild.rb"
          require "#{extension_path}/transport/autobuild"
          extension_class::Transport::AutoBuild.build
          log.warn 'still using transport::autobuild, please upgrade'
          return
        end

        if File.exist? "#{extension_path}/transport.rb"
          require "#{extension_path}/transport"
          unless extension_class::Transport.respond_to?(:build)
            log.warn "#{extension_class}::Transport does not respond to build, auto-generating"
            auto_generate_transport
          end
        else
          auto_generate_transport
        end
        extension_class::Transport.build
      end

      def build_settings
        if Legion::Settings[:extensions].key?(lex_name.to_sym)
          Legion::Settings[:default_extension_settings].each do |key, value|
            Legion::Settings[:extensions][lex_name.to_sym][key.to_sym] = if Legion::Settings[:extensions][lex_name.to_sym].key?(key.to_sym)
                                                                           value.merge(Legion::Settings[:extensions][lex_name.to_sym][key.to_sym])
                                                                         else
                                                                           value
                                                                         end
          end
        else
          Legion::Settings[:extensions][lex_name.to_sym] = Legion::Settings[:default_extension_settings]
        end

        default_settings.each do |key, value|
          Legion::Settings[:extensions][lex_name.to_sym][key.to_sym] = if Legion::Settings[:extensions][lex_name.to_sym].key?(key.to_sym)
                                                                         value.merge(Legion::Settings[:extensions][lex_name.to_sym][key.to_sym])
                                                                       else
                                                                         value
                                                                       end
        end
      end

      def default_settings
        {}
      end

      def register_hooks
        return if @hooks.nil? || @hooks.empty?
        return unless defined?(Legion::API)

        # Find the first runner class as default for hooks that don't specify one
        default_runner = @runners.values.first&.dig(:runner_class)

        @hooks.each_value do |hook_info|
          Legion::API.register_hook(
            lex_name:       extension_name,
            hook_name:      hook_info[:hook_name],
            hook_class:     hook_info[:hook_class],
            default_runner: hook_info[:hook_class].new.runner_class || default_runner,
            route_path:     hook_info[:route_path]
          )
        end
      end

      def register_routes
        return if @routes.nil? || @routes.empty?
        return unless defined?(Legion::API)

        @routes.each_value do |route_info|
          Legion::API.register_route(
            lex_name:     route_info[:lex_name],
            runner_name:  route_info[:runner_name],
            function:     route_info[:function],
            runner_class: route_info[:runner_class],
            route_path:   route_info[:route_path]
          )
        end
      end

      def auto_generate_transport
        require 'legion/extensions/transport'
        log.debug 'running meta magic to generate a transport base class'
        if lex_class.const_defined?(:Transport, false)
          mod = lex_class.const_get(:Transport, false)
          mod.extend(Legion::Extensions::Transport) unless mod.respond_to?(:build)
        else
          lex_class.const_set(:Transport, Module.new { extend Legion::Extensions::Transport })
        end
      end

      def auto_generate_data
        require 'legion/extensions/data'
        log.debug 'running meta magic to generate a data base class'
        if lex_class.const_defined?(:Data, false)
          mod = lex_class.const_get(:Data, false)
          mod.extend(Legion::Extensions::Data) unless mod.respond_to?(:build)
        else
          lex_class.const_set(:Data, Module.new { extend Legion::Extensions::Data })
        end
      rescue StandardError => e
        log.log_exception(e, payload_summary: "[Core] auto_generate_data failed for #{name}", component_type: :builder)
      end
    end
  end
end
