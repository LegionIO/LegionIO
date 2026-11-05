# frozen_string_literal: true

require_relative 'exception'
require_relative 'runner/log'
require_relative 'runner/status'
require_relative 'context'
require 'legion/transport'
require 'legion/transport/messages/check_subtask'
require 'legion/transport/task/protocol'

module Legion
  module Runner
    extend Legion::Transport::Task::Protocol::Helper

    module Failure
      attr_accessor :task_outcome
    end

    def self.run(runner_class:, function:, task_id: nil, args: nil, check_subtask: true, generate_task: true, # rubocop:disable Metrics/ParameterLists
                 parent_id: nil, master_id: nil, catch_exceptions: false, **opts)
      started_at = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      rlog = runner_logger(derive_lex_tag(runner_class))
      runner_class = Kernel.const_get(runner_class) if runner_class.is_a?(String)
      raise ArgumentError, 'function is required' if function.nil? || function.to_s.empty?
      raise ArgumentError, "unknown runner function #{runner_class}##{function}" unless runner_class.respond_to?(function)
      raise ArgumentError, 'runner args must be a Hash' unless args.nil? || args.is_a?(Hash)

      args = (args || opts.except(*Legion::Transport::Task::Protocol::METADATA_FIELDS, :'x-retry-count')).dup
      if task_id.nil? && generate_task
        generated = Legion::Runner::Status.generate_task_id(runner_class: runner_class, function: function,
                                                            parent_id: parent_id, master_id: master_id, args: args, **opts)
        task_id = generated[:task_id] if generated
      end
      context = opts.slice(*Legion::Transport::Task::Protocol::METADATA_FIELDS)
                    .merge(task_id: task_id, parent_id: parent_id, master_id: master_id,
                           runner_class: runner_class.to_s, function: function.to_s)
      if task_id || parent_id || master_id
        args.delete(:task_id)
        args.delete(:parent_id)
        args.delete(:master_id)
        args.merge!(context.slice(:task_id, :parent_id, :master_id).compact)
      end
      result, status, error = execute_runner(context: context, runner_class: runner_class, args: args, rlog: rlog)
      outcome = { success: status == task_status(name: :completed), status: status, result: result, task_id: task_id, executed: true }
      duration_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      rlog.info "[Runner] complete: #{runner_class}##{function} status=#{status} duration_ms=#{duration_ms}"
      audit_outcome(context: context, outcome: outcome, duration_ms: duration_ms, rlog: rlog)
      begin
        Legion::Runner::Status.update(task_id: task_id, status: status, results: result) unless task_id.nil?
        Legion::Events.emit(task_status(name: outcome[:success] ? :completed : :failed), **context.slice(:runner_class, :function), **outcome)
        Legion::Transport::Messages::CheckSubtask.new(**context, result: result, original_args: args).publish! if outcome[:success] && check_subtask
      rescue StandardError => e
        rlog.error "[Runner] completion failed: #{e.class}: #{e.message}"
        failure = error && !catch_exceptions ? error : e
        failure.extend(Failure)
        failure.task_outcome = outcome
        raise failure
      end
      if error && !catch_exceptions
        error.extend(Failure)
        error.task_outcome = outcome
        raise error
      end
      outcome
    end

    def self.execute_runner(context:, runner_class:, args:, rlog:)
      function = context[:function]
      rlog.info "[Runner] start: #{runner_class}##{function} task_id=#{context[:task_id]}"
      result = Legion::Context.with_task_context(context) do
        if runner_class.respond_to?(:with_log_context)
          runner_class.with_log_context(function) { runner_class.public_send(function, **args) }
        else
          runner_class.public_send(function, **args)
        end
      end
      raise TypeError, 'runner functions must return a Hash' unless result.is_a?(Hash)

      [result, returned_status(result: result), nil]
    rescue StandardError => e
      rlog.error "[Runner] exception in #{runner_class}##{function}: #{e.class}: #{e.message}"
      status = task_status(name: :exception)
      result = { success: false, status: status, error: { class: e.class.to_s, message: e.message, backtrace: e.backtrace } }
      notify_exception(runner_class: runner_class, error: e, context: context, args: args, rlog: rlog)
      [result, status, e]
    end

    def self.returned_status(result:)
      status = result[:status]
      return status if %i[skipped cancelled expired unknown].any? { |name| status == task_status(name: name) }
      if result[:success] == false || (status && task_terminal_status?(status: status) && status != task_status(name: :completed))
        return task_status(name: :failed)
      end

      task_status(name: :completed)
    end

    def self.notify_exception(runner_class:, error:, context:, args:, rlog:)
      return unless runner_class.respond_to?(:handle_runner_exception)

      runner_class.handle_runner_exception(error, **context, args: args)
    rescue StandardError => e
      rlog.warn "[Runner] exception handler failed: #{e.class}: #{e.message}"
    end

    def self.audit_outcome(context:, outcome:, duration_ms:, rlog:)
      return unless defined?(Legion::Audit)

      error = outcome[:result].is_a?(Hash) ? outcome[:result][:error] : nil
      detail = context.slice(:originating_principal_id, :originating_principal_type)
                      .merge(task_id: outcome[:task_id], error: error.is_a?(Hash) ? error[:message] : error)
      Legion::Audit.record(event_type: 'runner_execution', principal_id: context[:principal_id] || context[:worker_id] || 'system',
                           principal_type: context[:principal_type] || 'system', action: 'execute',
                           resource: "#{context[:runner_class]}/#{context[:function]}", source: context[:source] || 'unknown',
                           status: outcome[:success] ? 'success' : 'failure', duration_ms: duration_ms,
                           detail: detail)
    rescue StandardError => e
      rlog.warn "[Runner] audit failed: #{e.message}"
    end

    def self.derive_lex_tag(runner_class)
      parts = runner_class.to_s.split('::')
      ext_idx = parts.index('Extensions')
      return parts.last.to_s.downcase unless ext_idx && parts[ext_idx + 1]

      parts[ext_idx + 1].gsub(/([A-Z]++)([A-Z][a-z])/, '\\1_\\2')
                        .gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
    end

    def self.runner_logger(tag)
      @runner_loggers ||= {}
      @runner_loggers[tag] ||= Legion::Logging::Logger.new(lex: tag)
    end
  end
end
