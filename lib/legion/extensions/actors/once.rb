# frozen_string_literal: true

require_relative 'base'
require_relative 'dsl'

module Legion
  module Extensions
    module Actors
      class Once
        extend Legion::Extensions::Actors::Dsl
        include Legion::Extensions::Actors::Base

        define_dsl_accessor :delay, default: 1.0

        def initialize(**)
          super()
          @tasks = []
          return unless enabled?

          if respond_to? :functions
            functions.each do
              function
              @tasks << Concurrent::ScheduledTask.execute(delay) do
                with_actor_execution { use_runner? ? runner : manual }
              end
            end
          else
            @tasks << Concurrent::ScheduledTask.execute(delay) do
              with_actor_execution { use_runner? ? runner : manual }
            end
          end
        rescue StandardError => e
          handle_exception(e, level: :error, operation: :once_initialize)
        end

        def delay
          1.0
        end

        def cancel(**)
          request_stop
          @tasks.each(&:cancel)
          true
        end
      end
    end
  end
end
