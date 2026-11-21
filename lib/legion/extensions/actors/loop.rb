# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Actors
      class Loop
        include Concurrent::Async
        include Legion::Extensions::Actors::Base

        def initialize(**)
          super()
          @run_task = Concurrent::Future.execute { run }
        rescue StandardError => e
          handle_exception(e)
        end

        def run(**)
          with_actor_execution { action } until actor_stopping?
        rescue StandardError => e
          handle_exception(e, level: :error, operation: :loop_run)
          raise
        end

        def action(**_opts)
          Legion::Logging.warn 'An extension is using the default action for a loop'
        end

        def cancel(**)
          request_stop
        end

        def await_stopped(deadline: nil, **)
          return false unless super
          return true unless @run_task

          @run_task.wait(shutdown_remaining(deadline: deadline))
          @run_task.complete?
        end
      end
    end
  end
end
