# frozen_string_literal: true

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
rescue LoadError
  # legion-llm not installed, helper not available
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

      include Legion::Extensions::Builder::Runners
      include Legion::Extensions::Builder::Helpers
      include Legion::Extensions::Builder::Actors
      include Legion::Extensions::Builder::Hooks
      include Legion::Extensions::Builder::Routes

      def autobuild
        @actors = {}
        @meta_actors = {}
        @runners = {}
        @helpers = []

        @queues = {}
        @exchanges = {}
        @messages = {}
        build_settings
        build_transport
        build_data if Legion::Settings[:data][:connected] && data_required?
        build_helpers
        build_runners
        build_actors
        build_hooks
        build_routes
        register_hooks
        register_routes
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

      def build_data
        auto_generate_data
        lex_class::Data.build
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
        return if Kernel.const_defined? "#{lex_class}::Transport"

        Kernel.const_get(lex_class.to_s).const_set('Transport', Module.new { extend Legion::Extensions::Transport })
      end

      def auto_generate_data
        require 'legion/extensions/data'
        log.debug 'running meta magic to generate a data base class'
        return if Kernel.const_defined? "#{lex_class}::Data"

        Kernel.const_get(lex_class.to_s).const_set('Data', Module.new { extend Legion::Extensions::Data })
      rescue StandardError => e
        log.error e.message
        log.error e.backtrace
      end
    end
  end
end
