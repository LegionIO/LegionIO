# frozen_string_literal: true

require_relative 'runner/log'
require_relative 'runner/status'
require_relative 'context'
require 'legion/transport'
require 'legion/transport/messages/check_subtask'
require 'legion/task_execution'
require 'legion/transport/task_protocol'
require 'time'
require 'concurrent'

module Legion
  module Runner
    extend Legion::TaskExecution::Helper
    extend Legion::Transport::TaskProtocol::Helper

    # Preserve the original exception class/backtrace while giving the consumer
    # the recorded outcome. A publication failure must never rerun external effects.
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

      opts = opts.except(:execution_policy)
      args = (args || opts.except(*Legion::Transport::TaskProtocol::METADATA_FIELDS, :'x-retry-count')).dup
      if task_id.nil? && generate_task
        generated = Legion::Runner::Status.generate_task_id(runner_class: runner_class, function: function,
                                                            parent_id: parent_id, master_id: master_id, args: args, **opts)
        task_id = generated[:task_id] if generated
      end
      context = opts.merge(task_id: task_id, parent_id: parent_id, master_id: master_id,
                           runner_class: runner_class.to_s, function: function.to_s)
      persisted = Legion::Runner::Status.data_connected? && !task_id.nil?
      claim = if persisted
                Legion::Data::TaskExecution.claim_task(task_id: task_id, owner: Legion::Settings[:client][:name])
              else
                { claimed: true, token: nil, attempt_id: nil }
              end
      return claim_outcome(claim: claim, task_id: task_id) unless claim[:claimed]

      context[:attempt_id] = claim[:attempt_id]
      context[:execution_token] = claim[:token]
      context[:execution_policy] = claim.fetch(:policy) if persisted
      context[:attempt_number] = claim[:task][:attempt_count] if persisted
      context.merge!(claim[:task].slice(:parent_id, :master_id, :relationship_id, :function_id, :depth, :deadline_at)) if persisted
      args.delete(:task_id)
      args.delete(:parent_id)
      args.delete(:master_id)
      args.merge!(context.slice(:task_id, :parent_id, :master_id).compact)
      status = pre_execution_status(context: context) unless persisted
      result = { success: false, status: status } if status
      result, status, error = execute_runner(context: context, runner_class: runner_class, args: args, persisted: persisted, rlog: rlog) unless status

      outcome = finish_execution(context: context, args: args, result: result, status: status,
                                 persisted: persisted, check_subtask: check_subtask)
      duration_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      rlog.info "[Runner] complete: #{runner_class}##{function} status=#{outcome[:status]} duration_ms=#{duration_ms}"
      audit_outcome(context: context, outcome: outcome, duration_ms: duration_ms, rlog: rlog)
      if error && !catch_exceptions
        error.extend(Failure)
        error.task_outcome = outcome
        raise error
      end
      outcome
    end

    def self.execute_runner(context:, runner_class:, args:, persisted:, rlog:)
      function = context[:function]
      rlog.info "[Runner] start: #{runner_class}##{function} task_id=#{context[:task_id]}"
      heartbeat = start_execution_heartbeat(context: context, rlog: rlog) if persisted
      error = nil
      begin
        result = Legion::Context.with_task_context(context) do
          if runner_class.respond_to?(:with_log_context)
            runner_class.with_log_context(function) { runner_class.public_send(function, **args) }
          else
            runner_class.public_send(function, **args)
          end
        end
        raise TypeError, 'runner functions must return a Hash' unless result.is_a?(Hash)

        status = returned_status(result: result)
      rescue StandardError => e
        error = e
        rlog.error "[Runner] exception in #{runner_class}##{function}: #{e.class}: #{e.message}"
        status = exception_status(context: context)
        result = { success: false, status: task_status(name: :exception), error: { class: e.class.to_s, message: e.message, backtrace: e.backtrace } }
        notify_exception(runner_class: runner_class, error: e, context: context, args: args, rlog: rlog)
      ensure
        stop_execution_heartbeat(heartbeat: heartbeat, rlog: rlog) if heartbeat
      end
      if heartbeat && !heartbeat[:owned].true?
        status = task_status(name: :unknown)
        result = { success: false, status: status, result: result, error: { code: 'execution_lease_lost' } }
      end
      [result, status, error]
    end

    def self.start_execution_heartbeat(context:, rlog:)
      owned = Concurrent::AtomicBoolean.new(true)
      interval = context.fetch(:execution_policy).fetch(:execution).fetch(:heartbeat_seconds)
      timer = Concurrent::TimerTask.new(execution_interval: interval) do
        renewal = Legion::Data::TaskExecution.renew_task_lease(task_id: context[:task_id], token: context[:execution_token])
        owned.make_false unless renewal[:renewed]
      rescue StandardError => e
        owned.make_false
        rlog.error "[Runner] execution lease renewal failed: #{e.class}: #{e.message}"
      end
      timer.execute
      { timer: timer, owned: owned, interval: interval }
    end

    def self.stop_execution_heartbeat(heartbeat:, rlog:)
      heartbeat[:timer].shutdown
      return if heartbeat[:timer].wait_for_termination(heartbeat[:interval])

      heartbeat[:owned].make_false
      rlog.error '[Runner] execution lease renewal did not stop before completion'
    rescue StandardError => e
      heartbeat[:owned].make_false
      rlog.error "[Runner] execution lease shutdown failed: #{e.class}: #{e.message}"
    end

    def self.claim_outcome(claim:, task_id:)
      task = claim[:task] || {}
      result = task[:results].is_a?(String) ? Legion::JSON.load(task[:results]) : task[:results]
      { success: task[:status] == task_status(name: :completed), status: task[:status], result: result,
        task_id: task_id, attempt_id: claim[:attempt_id], persisted: true, executed: false, reason: claim[:reason] }
    end

    def self.pre_execution_status(context:)
      return task_status(name: :cancelled) if context[:cancelled_at]
      return unless context[:deadline_at]

      deadline = context[:deadline_at].is_a?(Time) ? context[:deadline_at] : Time.parse(context[:deadline_at].to_s)
      task_status(name: :expired) if deadline <= Time.now
    end

    def self.returned_status(result:)
      status = result[:status]
      return status if %i[skipped cancelled expired unknown].any? { |name| status == task_status(name: name) }
      if result[:success] == false || (status && task_terminal_status?(status: status) && status != task_status(name: :completed))
        return task_status(name: :failed)
      end

      task_status(name: :completed)
    end

    def self.exception_status(context:)
      local_policy = task_execution_settings[:retry]
      target = "#{context[:runner_class]}##{context[:function]}"
      safe = local_policy[:safe_runners].fetch(target.to_sym) { local_policy[:safe_runners][target] }
      return task_status(name: :unknown) unless safe == true

      policy = context[:execution_policy] ? context[:execution_policy].fetch(:retry) : local_policy
      attempts = context[:attempt_number] || (context.fetch(:'x-retry-count', 0).to_i + 1)
      task_status(name: attempts < policy[:max_attempts] ? :retry_pending : :exception)
    end

    def self.finish_execution(context:, args:, result:, status:, persisted:, check_subtask:) # rubocop:disable Metrics/ParameterLists
      success = status == task_status(name: :completed)
      options = context.slice(*Legion::Transport::TaskProtocol::METADATA_FIELDS).merge(result: result, original_args: args)
      continuation = if success && check_subtask
                       { event_key: "task:#{context[:task_id]}:completed",
                         message_type: Legion::Transport::TaskProtocol::MESSAGE_TYPES[:check_subtask], options: options }
                     end
      changed = true
      if persisted
        completion = Legion::Data::TaskExecution.complete_task(task_id: context[:task_id], status: status, result: result,
                                                               token: context[:execution_token], continuation: continuation)
        changed = completion[:changed]
        status = completion[:task][:status]
        success = status == task_status(name: :completed)
        unless changed
          stored_result = completion[:task][:results]
          result = stored_result.is_a?(String) ? Legion::JSON.load(stored_result) : stored_result
        end
      end
      outcome = { success: success, status: status, result: result, task_id: context[:task_id],
                  attempt_id: context[:attempt_id], persisted: persisted, executed: true }
      outcome[:retry_at] = completion[:task][:retry_at] if persisted && status == task_status(name: :retry_pending)
      if changed
        Legion::Events.emit(task_status(name: success ? :completed : :failed), **context.slice(:runner_class, :function), **outcome)
        publish_ephemeral_continuation(options: options, outcome: outcome) if continuation && !persisted
      end
      outcome
    rescue StandardError => e
      e.extend(Failure)
      e.task_outcome ||= { success: false, status: task_status(name: :unknown), task_id: context[:task_id], persisted: persisted }
      raise
    end

    def self.publish_ephemeral_continuation(options:, outcome:)
      Legion::Transport::Messages::CheckSubtask.new(**options).publish!
    rescue StandardError => e
      e.extend(Failure)
      e.task_outcome = outcome
      raise
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
