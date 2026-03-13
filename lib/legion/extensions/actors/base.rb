# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Base
        include Legion::Extensions::Helpers::Lex

        def runner
          Legion::Runner.run(runner_class: runner_class, function: function, check_subtask: check_subtask?, generate_task: generate_task?)
        rescue StandardError => e
          Legion::Logging.error e.message
          Legion::Logging.error e.backtrace
        end

        def manual
          runner_class.send(runner_function, **args)
        rescue StandardError => e
          Legion::Logging.error e.message
          Legion::Logging.error e.backtrace
        end

        def function
          nil
        end

        def use_runner?
          true
        end

        def args
          {}
        end

        def check_subtask?
          true
        end

        def generate_task?
          false
        end

        def enabled?
          true
        end
      end
    end
  end
end
