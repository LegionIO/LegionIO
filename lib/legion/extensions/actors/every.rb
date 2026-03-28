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
          @timer = Concurrent::TimerTask.new(execution_interval: time, run_now: run_now?) do
            log.debug "[Every] tick: #{self.class}" if defined?(log)
            begin
              skip_or_run { use_runner? ? runner : manual }
            rescue StandardError => e
              log.log_exception(e, payload_summary: "[Every] tick failed for #{self.class}", component_type: :actor) if defined?(log)
            end
          end

          @timer.execute
        rescue StandardError => e
          log.log_exception(e, component_type: :actor)
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
          log.log_exception(e, component_type: :actor)
        end
      end
    end
  end
end
