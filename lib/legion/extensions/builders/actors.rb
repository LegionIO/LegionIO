# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Actors
        include Legion::Extensions::Builder::Base

        attr_reader :actors

        def build_actors
          @actors = {}
          require_files(actor_files)
          build_actor_list
          build_meta_actor_list
        end

        def build_actor_list
          actor_files.each do |file|
            actor_name = file.split('/').last.sub('.rb', '')
            actor_class = "#{lex_class}::Actor::#{actor_name.split('_').collect(&:capitalize).join}"
            unless Kernel.const_defined?(actor_class)
              Legion::Logging.warn "Actor constant #{actor_class} not defined, skipping"
              next
            end
            @actors[actor_name.to_sym] = {
              extension:      lex_class.to_s.downcase,
              extension_name: extension_name,
              actor_name:     actor_name,
              actor_class:    Kernel.const_get(actor_class),
              type:           'literal'
            }
          end
        end

        def build_meta_actor_list
          @runners.each do |runner, attr|
            next if @actors[runner.to_sym].is_a? Hash

            actor_class = "#{attr[:extension_class]}::Actor::#{runner.to_s.split('_').collect(&:capitalize).join}"
            build_meta_actor(runner, attr) unless Kernel.const_defined? actor_class
            @actors[runner.to_sym] = {
              extension:      attr[:extension],
              extension_name: attr[:extension_name],
              actor_name:     attr[:runner_name],
              actor_class:    Kernel.const_get(actor_class),
              type:           'meta'
            }
          end
        end

        def build_meta_actor(runner, attr)
          define_constant_two('Actor', root: lex_class)

          Kernel.const_get("#{attr[:extension_class]}::Actor")
                .const_set(runner.to_s.split('_').collect(&:capitalize).join, Class.new(Legion::Extensions::Actors::Subscription))
        end

        def actor_files
          @actor_files ||= find_files('actors')
        end
      end
    end
  end
end
