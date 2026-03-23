# frozen_string_literal: true

require_relative 'base'
require_relative 'fingerprint'

module Legion
  module Extensions
    module Actors
      class Every
        include Legion::Extensions::Actors::Base
        include Legion::Extensions::Actors::Fingerprint

        def initialize(**_opts)
          @timer = Concurrent::TimerTask.new(execution_interval: time, run_now: run_now?) do
            log.debug "[Every] tick: #{self.class}" if defined?(log)
            begin
              skip_or_run { use_runner? ? runner : manual }
            rescue StandardError => e
              log.error "[Every] tick failed for #{self.class}: #{e.message}" if defined?(log)
              log.error e.backtrace if defined?(log)
            end
          end

          @timer.execute
        rescue StandardError => e
          log.error e.message
          log.error e.backtrace
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
          log.warn 'An extension is using the default block from Legion::Extensions::Runners::Every'
        end

        def cancel
          log.debug 'Cancelling Legion Timer'
          return true unless @timer.respond_to?(:shutdown)

          @timer.shutdown
        rescue StandardError => e
          log.error e.message
          log.error e.backtrace
        end
      end
    end
  end
end
