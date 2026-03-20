# frozen_string_literal: true

require_relative 'base'
require_relative 'fingerprint'
require 'time'

module Legion
  module Extensions
    module Actors
      class Poll
        include Legion::Extensions::Actors::Base
        include Legion::Extensions::Actors::Fingerprint

        def initialize
          log.debug "Starting timer for #{self.class} with #{{ execution_interval: time, run_now: run_now?,
check_subtask: check_subtask? }}"
          @timer = Concurrent::TimerTask.new(execution_interval: time, run_now: run_now?) do
            skip_or_run { poll_cycle }
          rescue StandardError => e
            Legion::Logging.fatal e.message
            Legion::Logging.fatal e.backtrace
          end
          @timer.execute
        rescue StandardError => e
          Legion::Logging.error e.message
          Legion::Logging.error e.backtrace
        end

        def poll_cycle
          t1 = Time.now
          log.debug "Running #{self.class}"
          old_result = Legion::Cache.get(cache_name)
          log.debug "Cached value for #{self.class}: #{old_result}"
          results = Legion::JSON.load(Legion::JSON.dump(manual))
          Legion::Cache.set(cache_name, results, time * 2)

          unless old_result.nil?
            results[:diff] = Hashdiff.diff(results, old_result, numeric_tolerance: 0.0, array_path: false) do |_path, obj1, obj2|
              if int_percentage_normalize.positive? && obj1.is_a?(Integer) && obj2.is_a?(Integer)
                obj1.between?(obj2 * (1 - int_percentage_normalize), obj2 * (1 + int_percentage_normalize))
              end
            end
            results[:changed] = results[:diff].any?

            Legion::Logging.info results[:diff] if results[:changed]
            Legion::Transport::Messages::CheckSubtask.new(runner_class: runner_class.to_s,
                                                          function:     runner_function,
                                                          result:       results,
                                                          type:         'poll_result',
                                                          polling:      true).publish
          end

          sleep_time = 1 - (Time.now - t1)
          sleep(sleep_time) if sleep_time.positive?
          log.debug("#{self.class} result: #{results}")
          results
        rescue StandardError => e
          Legion::Logging.fatal e.message
          Legion::Logging.fatal e.backtrace
        end

        def cache_name
          "#{lex_name}_#{runner_name}"
        end

        def int_percentage_normalize
          0.00
        end

        def time
          9
        end

        def run_now?
          true
        end

        def check_subtask?
          true
        end

        def timeout
          5
        end

        def action(_payload = {})
          Legion::Logging.warn 'An extension is using the default block from Legion::Extensions::Runners::Every'
        end

        def cancel
          Legion::Logging.debug 'Cancelling Legion Poller'
          @timer.shutdown
        rescue StandardError => e
          Legion::Logging.error e.message
        end
      end
    end
  end
end
