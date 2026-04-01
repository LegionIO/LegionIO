# frozen_string_literal: true

require_relative 'dsl'

module Legion
  module Extensions
    module Actors
      module Base
        extend Legion::Extensions::Actors::Dsl
        include Legion::Extensions::Helpers::Lex

        define_dsl_accessor :use_runner, default: true
        define_dsl_accessor :check_subtask, default: true
        define_dsl_accessor :generate_task, default: false
        define_dsl_accessor :enabled, default: true
        define_dsl_accessor :remote_invocable, default: true

        def runner
          with_log_context(function) do
            Legion::Runner.run(runner_class: runner_class, function: function,
                               check_subtask: check_subtask?, generate_task: generate_task?)
          end
        rescue StandardError => e
          handle_exception(e)
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
          handle_exception(e)
        end

        def function
          nil
        end

        def self.included(base)
          base.extend(Legion::Extensions::Actors::Dsl) unless base.singleton_class.include?(Legion::Extensions::Actors::Dsl)
          base.define_dsl_accessor(:use_runner, default: true) unless base.respond_to?(:use_runner)
          base.define_dsl_accessor(:check_subtask, default: true) unless base.respond_to?(:check_subtask)
          base.define_dsl_accessor(:generate_task, default: false) unless base.respond_to?(:generate_task)
          base.define_dsl_accessor(:enabled, default: true) unless base.respond_to?(:enabled)
          base.define_dsl_accessor(:remote_invocable, default: true) unless base.respond_to?(:remote_invocable)
        end

        def use_runner?
          self.class.respond_to?(:use_runner) ? self.class.use_runner : true
        end

        def args
          {}
        end

        def check_subtask?
          self.class.respond_to?(:check_subtask) ? self.class.check_subtask : true
        end

        def generate_task?
          self.class.respond_to?(:generate_task) ? self.class.generate_task : false
        end

        def enabled?
          self.class.respond_to?(:enabled) ? self.class.enabled : true
        end

        def remote_invocable?
          self.class.respond_to?(:remote_invocable) ? self.class.remote_invocable : true
        end
      end
    end
  end
end
