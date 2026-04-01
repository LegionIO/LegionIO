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
          @executing = Concurrent::AtomicBoolean.new(false)
          @timer = Concurrent::TimerTask.new(execution_interval: time, run_now: run_now?) do
            if @executing.make_true
              begin
                log.debug "[Every] tick: #{self.class}" if defined?(log)
                skip_or_run { use_runner? ? runner : manual }
              rescue StandardError => e
                log.error "[Every] tick failed for #{self.class}: #{e.class}: #{e.message}" if defined?(log)
                handle_exception(e) if defined?(log)
              ensure
                @executing.make_false
              end
            elsif defined?(log)
              log.debug "[Every] skipped (previous still running): #{self.class}"
            end
          end

          @timer.execute
        rescue StandardError => e
          handle_exception(e)
        end

        def run_now?
          run_now
        end

        def action(**_opts)
          log.warn 'An extension is using the default block from Legion::Extensions::Runners::Every'
        end

        def cancel
          log.debug 'Cancelling Legion Timer'
          return true unless @timer.respond_to?(:shutdown)

          @timer.shutdown
        rescue StandardError => e
          handle_exception(e)
        end
      end
    end
  end
end
