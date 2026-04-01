# frozen_string_literal: true

module Legion
  module Ingress
    MAX_PAYLOAD_SIZE = 524_288 # 512KB serialized
    RUNNER_CLASS_PATTERN = /\A[A-Z][A-Za-z0-9:]+\z/
    FUNCTION_PATTERN = /\A[a-z_][a-z0-9_]*[!?]?\z/

    class PayloadTooLarge < StandardError; end
    class InvalidRunnerClass < StandardError; end
    class InvalidFunction < StandardError; end

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

        if message.is_a?(Hash) && defined?(Legion::JSON)
          serialized_size = Legion::JSON.dump(message).bytesize
          raise PayloadTooLarge, "payload exceeds #{MAX_PAYLOAD_SIZE} bytes" if serialized_size > MAX_PAYLOAD_SIZE
        end

        message[:runner_class] = runner_class || message[:runner_class]
        message[:function] = function || message[:function]
        message[:source] = source
        message[:timestamp] ||= Time.now.to_i
        message[:datetime] ||= Time.at(message[:timestamp]).to_datetime.to_s
        message.merge(opts)
      end

      # Normalize and execute via Legion::Runner.run.
      # Returns the runner result hash.
      def run(payload:, runner_class: nil, function: nil, source: 'unknown', principal: nil, **opts) # rubocop:disable Metrics/ParameterLists,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize
        Legion::Logging.info "[Ingress] run: source=#{source} runner_class=#{runner_class} function=#{function}" if defined?(Legion::Logging)
        check_subtask = opts.fetch(:check_subtask, true)
        generate_task = opts.fetch(:generate_task, true)
        message = normalize(payload: payload, runner_class: runner_class,
                            function: function, source: source,
                            **opts.except(:check_subtask, :generate_task, :principal))

        Legion::Logging.debug "[Ingress] payload keys: #{message.keys}" if defined?(Legion::Logging)

        rc = message.delete(:runner_class)
        fn = message.delete(:function)

        if rc.nil?
          Legion::Logging.warn '[Ingress] runner_class is missing' if defined?(Legion::Logging)
          raise 'runner_class is required'
        end
        raise 'function is required' if fn.nil?

        rc_str = rc.to_s
        raise InvalidRunnerClass, "invalid runner_class format: #{rc_str}" unless rc_str.match?(RUNNER_CLASS_PATTERN)

        fn_str = fn.to_s
        raise InvalidFunction, "invalid function format: #{fn_str}" unless fn_str.match?(FUNCTION_PATTERN)

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

        if local_runner?(rc)
          Legion::Logging.debug "[Ingress] local short-circuit: #{rc}.#{fn}" if defined?(Legion::Logging)
          klass = rc.is_a?(String) ? Kernel.const_get(rc) : rc
          return Legion::Context.with_task_context(message) { klass.send(fn.to_sym, **message) }
        end

        runner_block = lambda {
          Legion::Context.with_task_context(message) do
            Legion::Runner.run(
              runner_class:  rc,
              function:      fn,
              check_subtask: check_subtask,
              generate_task: generate_task,
              **message
            )
          end
        }

        if defined?(Legion::Telemetry::OpenInference)
          Legion::Telemetry::OpenInference.tool_span(name: "#{rc}.#{fn}", parameters: message) { |_span| runner_block.call }
        else
          runner_block.call
        end
      rescue PayloadTooLarge => e
        Legion::Logging.error "[Ingress] payload_too_large: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'payload_too_large', message: e.message } }
      rescue InvalidRunnerClass => e
        Legion::Logging.error "[Ingress] invalid_runner_class: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'invalid_runner_class', message: e.message } }
      rescue InvalidFunction => e
        Legion::Logging.error "[Ingress] invalid_function: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'invalid_function', message: e.message } }
      rescue Legion::DigitalWorker::Registry::WorkerNotFound => e
        Legion::Logging.error "[Ingress] worker_not_found: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'worker_not_found', message: e.message } }
      rescue Legion::DigitalWorker::Registry::WorkerNotActive => e
        Legion::Logging.error "[Ingress] worker_not_active: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'worker_not_active', message: e.message } }
      rescue Legion::DigitalWorker::Registry::InsufficientConsent => e
        Legion::Logging.error "[Ingress] insufficient_consent: #{e.message}" if defined?(Legion::Logging)
        { success: false, status: 'task.blocked', error: { code: 'insufficient_consent', message: e.message } }
      end

      def local_runner?(runner_class)
        return false unless defined?(Legion::Extensions) && Legion::Extensions.local_tasks.is_a?(Array)

        klass = runner_class.is_a?(String) ? Kernel.const_get(runner_class) : runner_class
        Legion::Extensions.local_tasks.any? { |t| t[:runner_module] == klass }
      rescue NameError
        false
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
