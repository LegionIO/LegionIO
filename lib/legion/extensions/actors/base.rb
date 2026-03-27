# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Base
        include Legion::Extensions::Helpers::Lex

        def runner
          Legion::Runner.run(runner_class: runner_class, function: function, check_subtask: check_subtask?, generate_task: generate_task?)
        rescue StandardError => e
          Legion::Logging.log_exception(e, component_type: :actor)
        end

        def manual
          klass = runner_class
          klass = Kernel.const_get(klass) if klass.is_a?(String)
          func = respond_to?(:runner_function) ? runner_function : :action
          if klass == self.class
            send(func, **args)
          else
            klass.send(func, **args)
          end
        rescue StandardError => e
          Legion::Logging.log_exception(e, component_type: :actor)
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

        def remote_invocable?
          true
        end
      end
    end
  end
end
