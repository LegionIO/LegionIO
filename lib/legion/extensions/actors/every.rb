# frozen_string_literal: true

require_relative 'base'
require_relative 'fingerprint'
require_relative 'dsl'

module Legion
  module Extensions
    module Actors
      class Every
        extend Legion::Extensions::Actors::Dsl
        include Legion::Extensions::Actors::Base
        include Legion::Extensions::Actors::Fingerprint

        define_dsl_accessor :time, default: 1
        define_dsl_accessor :timeout, default: 5
        define_dsl_accessor :run_now, default: false

        def initialize(**_opts)
          super()
          @executing = Concurrent::AtomicBoolean.new(false)
          @timer = Concurrent::TimerTask.new(execution_interval: time, run_now: run_now?) do
            with_actor_execution do
              if @executing.make_true
                begin
                  log.debug "[Every] tick: #{self.class}"
                  skip_or_run { use_runner? ? runner : manual }
                rescue StandardError => e
                  handle_exception(e, level: :error, operation: :every_tick)
                ensure
                  @executing.make_false
                end
              else
                log.debug "[Every] skipped (previous still running): #{self.class}"
              end
            end
          end

          initial_delay = respond_to?(:delay) ? delay.to_f : 0
          if initial_delay.positive?
            @delayed_start = Concurrent::ScheduledTask.execute(initial_delay) do
              @actor_lifecycle_mutex.synchronize { @timer.execute unless @actor_stopping }
            end
          else
            @timer.execute
          end
        rescue StandardError => e
          handle_exception(e)
        end

        def run_now?
          run_now
        end

        def action(**_opts)
          log.warn 'An extension is using the default block from Legion::Extensions::Runners::Every'
        end

        def cancel(**)
          request_stop
          log.debug 'Cancelling Legion Timer'
          @delayed_start&.cancel
          @timer&.shutdown
          true
        end
      end
    end
  end
end
