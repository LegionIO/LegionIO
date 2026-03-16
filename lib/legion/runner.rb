# frozen_string_literal: true

require_relative 'runner/log'
require_relative 'runner/status'
require 'legion/transport'
require 'legion/transport/messages/check_subtask'

module Legion
  module Runner
    def self.run(runner_class:, function:, task_id: nil, args: nil, check_subtask: true, generate_task: true, parent_id: nil, master_id: nil, catch_exceptions: false, **opts) # rubocop:disable Layout/LineLength, Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/MethodLength, Metrics/PerceivedComplexity
      started_at = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      runner_class = Kernel.const_get(runner_class) if runner_class.is_a? String

      if task_id.nil? && generate_task
        task_gen = Legion::Runner::Status.generate_task_id(
          function: function,
          runner_class: runner_class,
          parent_id: parent_id, master_id: master_id, task_id: task_id, **opts
        )
        task_id = task_gen[:task_id] unless task_gen.nil?
      end

      args = opts if args.nil?
      args[:task_id] = task_id unless task_id.nil?
      args[:master_id] = master_id unless master_id.nil?
      args[:parent_id] = parent_id unless parent_id.nil?

      # result = Fiber.new { Fiber.yield runner_class.send(function, **args) }
      raise 'No Function defined' if function.nil?

      result = runner_class.send(function, **args)
    rescue Legion::Exception::HandledTask
      status = 'task.exception'
      result = { error: {} }
    rescue StandardError => e
      runner_class.handle_exception(e,
                                    **opts,
                                    runner_class:  runner_class,
                                    args:          args,
                                    function:      function,
                                    task_id:       task_id,
                                    generate_task: generate_task,
                                    check_subtask: check_subtask)
      status = 'task.exception'
      result = { success: false, status: status, error: { message: e.message, backtrace: e.backtrace } }
      raise e unless catch_exceptions
    ensure
      status = 'task.completed' if status.nil?
      Legion::Events.emit("task.#{status == 'task.completed' ? 'completed' : 'failed'}",
                          task_id: task_id, runner_class: runner_class.to_s, function: function, status: status)
      Legion::Runner::Status.update(task_id: task_id, status: status) unless task_id.nil?
      if check_subtask && status == 'task.completed'
        Legion::Transport::Messages::CheckSubtask.new(runner_class:  runner_class,
                                                      function:      function,
                                                      result:        result,
                                                      original_args: args,
                                                      **opts).publish
      end
      if defined?(Legion::Audit)
        begin
          duration_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          error_message = status == 'task.exception' ? result&.dig(:error, :message) : nil
          Legion::Audit.record(
            event_type:     'runner_execution',
            principal_id:   opts[:principal_id] || opts[:worker_id] || 'system',
            principal_type: opts[:principal_type] || 'system',
            action:         'execute',
            resource:       "#{runner_class}/#{function}",
            source:         opts[:source] || 'unknown',
            status:         status == 'task.completed' ? 'success' : 'failure',
            duration_ms:    duration_ms,
            detail:         { task_id: task_id, error: error_message }
          )
        rescue StandardError => e
          Legion::Logging.debug("Audit in runner.run failed: #{e.message}") if defined?(Legion::Logging)
        end
      end
      return { success: true, status: status, result: result, task_id: task_id } # rubocop:disable Lint/EnsureReturn
    end
  end
end
