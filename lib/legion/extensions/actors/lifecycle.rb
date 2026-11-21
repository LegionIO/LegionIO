# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Lifecycle
        def initialize(**)
          initialize_actor_lifecycle
          super()
        end

        def request_stop(**)
          @actor_lifecycle_mutex.synchronize { @actor_stopping = true }
          true
        end

        def await_stopped(deadline: nil, **)
          @actor_lifecycle_mutex.synchronize do
            return false unless @actor_stopping
            return false if @actor_execution_threads.key?(Thread.current)

            while @actor_executions.positive?
              remaining = shutdown_remaining(deadline: deadline)
              return false if remaining && remaining <= 0

              @actor_lifecycle_condition.wait(@actor_lifecycle_mutex, remaining)
            end
          end
          true
        end

        def close(**)
          true
        end

        private

        def initialize_actor_lifecycle
          return if @actor_lifecycle_mutex

          @actor_lifecycle_mutex = Mutex.new
          @actor_lifecycle_condition = ConditionVariable.new
          @actor_stopping = false
          @actor_executions = 0
          @actor_execution_threads = {}
        end

        def with_actor_execution(delivery: false, **)
          entered = @actor_lifecycle_mutex.synchronize do
            next false if @actor_stopping && !delivery

            @actor_executions += 1
            @actor_execution_threads[Thread.current] = @actor_execution_threads.fetch(Thread.current, 0) + 1
            true
          end
          return unless entered

          yield
        ensure
          if entered
            @actor_lifecycle_mutex.synchronize do
              @actor_executions -= 1
              count = @actor_execution_threads.fetch(Thread.current) - 1
              if count.zero?
                @actor_execution_threads.delete(Thread.current)
              else
                @actor_execution_threads[Thread.current] = count
              end
              @actor_lifecycle_condition.broadcast
            end
          end
        end

        def actor_stopping?
          @actor_lifecycle_mutex.synchronize { @actor_stopping }
        end

        def shutdown_remaining(deadline:, **)
          [deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC), 0].max if deadline
        end

        def await_actor_thread(thread:, deadline:, **)
          return true unless thread
          return false if thread == Thread.current

          thread.join(shutdown_remaining(deadline: deadline))
          !thread.alive?
        end
      end
    end
  end
end
