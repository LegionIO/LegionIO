# frozen_string_literal: true

require 'legion/task_execution'
require 'legion/transport/task_protocol'

module Legion
  module Ingress
    extend Legion::TaskExecution::Helper
    extend Legion::Transport::TaskProtocol::Helper

    RUNNER_CLASS_PATTERN = /\A[A-Z][A-Za-z0-9:]+\z/
    FUNCTION_PATTERN = /\A[a-z_][a-z0-9_]*[!?]?\z/

    class PayloadTooLarge < StandardError; end
    class InvalidRunnerClass < StandardError; end
    class InvalidFunction < StandardError; end
    class Deferred < StandardError; end

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
          limit = task_execution_settings[:execution][:max_payload_bytes]
          raise PayloadTooLarge, "payload exceeds #{limit} bytes" if serialized_size > limit
        end

        message[:runner_class] = runner_class || message[:runner_class]
        message[:function] = function || message[:function]
        message[:source] = source
        message[:timestamp] ||= Time.now.to_i
        message[:datetime] ||= Time.at(message[:timestamp]).to_datetime.to_s
        message.merge(opts).except(:execution_policy)
      end

      # Normalize and execute via Legion::Runner.run.
      # Returns the runner result hash.
      def run(payload:, runner_class: nil, function: nil, source: 'unknown', principal: nil, # rubocop:disable Metrics/ParameterLists
              use_runner: true, **opts)
        Legion::Logging.info "[Ingress] run: source=#{source} runner_class=#{runner_class} function=#{function}" if defined?(Legion::Logging)
        check_subtask = opts.fetch(:check_subtask, true)
        generate_task = opts.fetch(:generate_task, true)
        message = normalize(payload: payload, source: source, **opts.except(:check_subtask, :generate_task, :principal))

        Legion::Logging.debug "[Ingress] payload keys: #{message.keys}" if defined?(Legion::Logging)

        rc = runner_class || message[:runner_class]
        fn = function || message[:function]
        if use_runner
          message.delete(:runner_class)
          message.delete(:function)
        end

        if rc.nil?
          Legion::Logging.warn '[Ingress] runner_class is missing' if defined?(Legion::Logging)
          raise 'runner_class is required'
        end
        raise 'function is required' if fn.nil?

        rc_str = rc.to_s
        raise InvalidRunnerClass, "invalid runner_class format: #{rc_str}" unless rc_str.match?(RUNNER_CLASS_PATTERN)

        fn_str = fn.to_s
        raise InvalidFunction, "invalid function format: #{fn_str}" unless fn_str.match?(FUNCTION_PATTERN)

        principal = authorize_execution!(runner_class: rc, function: fn, message: message, principal: principal)
        claimed_id = message.delete(:principal_id)
        claimed_type = message.delete(:principal_type)
        message[:originating_principal_id] ||= claimed_id
        message[:originating_principal_type] ||= claimed_type
        if principal
          message[:principal_id] = principal.id
          message[:principal_type] = principal.type
        end

        Legion::Events.emit('ingress.received', runner_class: rc.to_s, function: fn, source: source)

        execute(message: message, runner_class: rc, function: fn, use_runner: use_runner,
                check_subtask: check_subtask, generate_task: generate_task)
      rescue Deferred => e
        Legion::Logging.warn "[Ingress] deferred: #{e.message}"
        { success: false, status: task_status(name: :queued), deferred: true, error: { code: 'extension_quiescing', message: e.message } }
      rescue PayloadTooLarge => e
        Legion::Logging.error "[Ingress] payload_too_large: #{e.message}"
        { success: false, status: task_status(name: :blocked), error: { code: 'payload_too_large', message: e.message } }
      rescue InvalidRunnerClass => e
        Legion::Logging.error "[Ingress] invalid_runner_class: #{e.message}"
        { success: false, status: task_status(name: :blocked), error: { code: 'invalid_runner_class', message: e.message } }
      rescue InvalidFunction => e
        Legion::Logging.error "[Ingress] invalid_function: #{e.message}"
        { success: false, status: task_status(name: :blocked), error: { code: 'invalid_function', message: e.message } }
      rescue StandardError => e
        code = if defined?(Legion::DigitalWorker::Registry::WorkerNotFound) && e.is_a?(Legion::DigitalWorker::Registry::WorkerNotFound)
                 'worker_not_found'
               elsif defined?(Legion::DigitalWorker::Registry::WorkerNotActive) && e.is_a?(Legion::DigitalWorker::Registry::WorkerNotActive)
                 'worker_not_active'
               elsif defined?(Legion::DigitalWorker::Registry::InsufficientConsent) && e.is_a?(Legion::DigitalWorker::Registry::InsufficientConsent)
                 'insufficient_consent'
               elsif defined?(Legion::Rbac::AccessDenied) && e.is_a?(Legion::Rbac::AccessDenied)
                 'access_denied'
               end
        raise unless code

        Legion::Logging.warn "[Ingress] #{code}: #{e.message}"
        { success: false, status: task_status(name: :blocked), error: { code: code, message: e.message } }
      end

      def authorize_execution!(runner_class:, function:, message:, principal: nil)
        raise Deferred, "extension for #{runner_class} is not accepting new work" unless extension_dispatch_allowed?(runner_class)

        if defined?(Legion::DigitalWorker::Registry) && message[:worker_id]
          Legion::DigitalWorker::Registry.validate_execution!(worker_id: message[:worker_id], required_consent: message[:required_consent])
        end
        return principal unless defined?(Legion::Rbac)

        principal ||= Legion::Rbac::Principal.anonymous
        Legion::Rbac.authorize_execution!(principal: principal, runner_class: runner_class.to_s, function: function.to_s)
        principal
      end

      def local_runner?(runner_class)
        return false unless defined?(Legion::Extensions) && Legion::Extensions.local_tasks.is_a?(Array)

        klass = resolve_runner_class(runner_class)
        Legion::Extensions.local_tasks.any? { |t| t[:runner_module] == klass }
      rescue NameError, InvalidRunnerClass => e
        Legion::Logging.debug "[Ingress] local runner lookup: #{e.message}"
        false
      end

      def reset_runner_cache!
        @registered_runner_modules = nil
      end

      private

      def execute(message:, runner_class:, function:, use_runner:, **)
        resolved = begin
          resolve_runner_class(runner_class)
        rescue InvalidRunnerClass => e
          Legion::Logging.debug "[Ingress] runner lookup: #{e.message}"
          runner_class
        end
        context = message.merge(runner_class: runner_class.to_s, function: function.to_s)
        return Legion::Context.with_task_context(context) { resolved.public_send(function.to_sym, **message) } if !use_runner || local_runner?(runner_class)

        runner_block = lambda {
          Legion::Context.with_task_context(context) do
            Legion::Runner.run(**message.except(:principal, :use_runner, :check_subtask, :generate_task),
                               runner_class: resolved, function: function, **)
          end
        }
        if defined?(Legion::Telemetry::OpenInference)
          Legion::Telemetry::OpenInference.tool_span(name: "#{runner_class}.#{function}", parameters: message) { |_span| runner_block.call }
        else
          runner_block.call
        end
      end

      def extension_dispatch_allowed?(runner_class)
        return true unless defined?(Legion::Extensions) && Legion::Extensions.respond_to?(:dispatch_allowed_for_runner?)

        Legion::Extensions.dispatch_allowed_for_runner?(runner_class)
      end

      def resolve_runner_class(runner_class)
        return runner_class unless runner_class.is_a?(String)

        raise InvalidRunnerClass, "invalid runner_class format: #{runner_class}" unless runner_class.match?(RUNNER_CLASS_PATTERN)

        resolved = registered_runner_modules[runner_class]
        raise InvalidRunnerClass, "unregistered runner_class: #{runner_class}" unless resolved

        resolved
      end

      def registered_runner_modules
        return @registered_runner_modules if defined?(@registered_runner_modules) && @registered_runner_modules

        modules = {}
        if defined?(Legion::Extensions) && Legion::Extensions.respond_to?(:loaded_extension_modules)
          Legion::Extensions.loaded_extension_modules.each do |mod|
            modules[mod.to_s] = mod
          end
        end
        if defined?(Legion::Extensions) && Legion::Extensions.local_tasks.is_a?(Array)
          Legion::Extensions.local_tasks.each do |t|
            mod = t[:runner_module]
            modules[mod.to_s] = mod if mod
          end
        end
        @registered_runner_modules = modules
      end

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
