# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Actors
      class Every
        include Legion::Extensions::Actors::Base

        def initialize(**_opts)
          @timer = Concurrent::TimerTask.new(execution_interval: time, timeout_interval: timeout, run_now: run_now?) do
            use_runner? ? runner : manual
          end

          @timer.execute
        rescue StandardError => e
          Legion::Logging.error e.message
          Legion::Logging.error e.backtrace
        end

        def time
          1
        end

        def timeout
          5
        end

        def run_now?
          false
        end

        def action(**_opts)
          Legion::Logging.warn 'An extension is using the default block from Legion::Extensions::Runners::Every'
        end

        def cancel
          Legion::Logging.debug 'Cancelling Legion Timer'
          return true unless @timer.respond_to?(:shutdown)

          @timer.shutdown
        rescue StandardError => e
          Legion::Logging.error e.message
          Legion::Logging.error e.backtrace
        end
      end
    end
  end
end
