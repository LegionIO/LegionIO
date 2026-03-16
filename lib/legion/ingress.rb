# frozen_string_literal: true

module Legion
  module Ingress
    class << self
      # Normalize a payload from any source into a runner-compatible message hash.
      # This is the universal entry point — AMQP subscriptions, HTTP webhooks, CLI
      # commands, and API endpoints all feed through here.
      #
      # @param payload [Hash, String] raw payload (JSON string or hash)
      # @param runner_class [String, Class, nil] target runner class
      # @param function [String, Symbol, nil] target function name
      # @param source [String] origin identifier (amqp, http, cli, etc.)
      # @param opts [Hash] additional context merged into the message
      # @return [Hash] normalized message ready for Runner.run
      def normalize(payload:, runner_class: nil, function: nil, source: 'unknown', **opts)
        message = parse_payload(payload)
        message[:runner_class] = runner_class || message[:runner_class]
        message[:function] = function || message[:function]
        message[:source] = source
        message[:timestamp] ||= Time.now.to_i
        message[:datetime] ||= Time.at(message[:timestamp]).to_datetime.to_s
        message.merge(opts)
      end

      # Normalize and execute via Legion::Runner.run.
      # Returns the runner result hash.
      def run(payload:, runner_class: nil, function: nil, source: 'unknown', principal: nil, **opts) # rubocop:disable Metrics/ParameterLists
        check_subtask = opts.fetch(:check_subtask, true)
        generate_task = opts.fetch(:generate_task, true)
        message = normalize(payload: payload, runner_class: runner_class,
                            function: function, source: source,
                            **opts.except(:check_subtask, :generate_task, :principal))

        rc = message.delete(:runner_class)
        fn = message.delete(:function)

        raise 'runner_class is required' if rc.nil?
        raise 'function is required' if fn.nil?

        # RAI invariant #2: registration precedes permission
        if defined?(Legion::DigitalWorker::Registry) && message[:worker_id]
          Legion::DigitalWorker::Registry.validate_execution!(
            worker_id:        message[:worker_id],
            required_consent: message[:required_consent]
          )
        end

        if defined?(Legion::Rbac)
          principal ||= Legion::Rbac::Principal.local_admin
          Legion::Rbac.authorize_execution!(principal: principal, runner_class: rc.to_s, function: fn.to_s)
        end

        Legion::Events.emit('ingress.received', runner_class: rc.to_s, function: fn, source: source)

        Legion::Runner.run(
          runner_class:  rc,
          function:      fn,
          check_subtask: check_subtask,
          generate_task: generate_task,
          **message
        )
      rescue Legion::DigitalWorker::Registry::WorkerNotFound => e
        { success: false, status: 'task.blocked', error: { code: 'worker_not_found', message: e.message } }
      rescue Legion::DigitalWorker::Registry::WorkerNotActive => e
        { success: false, status: 'task.blocked', error: { code: 'worker_not_active', message: e.message } }
      rescue Legion::DigitalWorker::Registry::InsufficientConsent => e
        { success: false, status: 'task.blocked', error: { code: 'insufficient_consent', message: e.message } }
      end

      private

      def parse_payload(payload)
        case payload
        when Hash
          payload.transform_keys(&:to_sym)
        when String
          Legion::JSON.load(payload).transform_keys(&:to_sym)
        when NilClass
          {}
        else
          { value: payload }
        end
      end
    end
  end
end
