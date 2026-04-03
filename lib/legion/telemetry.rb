# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Telemetry
    extend Legion::Logging::Helper

    autoload :OpenInference, 'legion/telemetry/open_inference'
    autoload :SafetyMetrics, 'legion/telemetry/safety_metrics'

    module_function

    def otel_available?
      defined?(OpenTelemetry::Trace) &&
        OpenTelemetry::Trace.current_span != OpenTelemetry::Trace::Span::INVALID
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.otel_available')
      false
    end

    def enabled?
      defined?(OpenTelemetry::SDK) ? true : false
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.enabled')
      false
    end

    def with_span(name, kind: :internal, attributes: {}, &)
      unless enabled?
        return yield(nil) if block_given?

        return
      end

      log.debug { "[Telemetry] starting span=#{name} kind=#{kind}" }
      tracer = OpenTelemetry.tracer_provider.tracer('legion', Legion::VERSION)
      tracer.in_span(name, kind: kind, attributes: sanitize_attributes(attributes), &)
    rescue StandardError => e
      raise if block_given? && !otel_init_error?(e)

      handle_exception(e, level: :debug, operation: 'telemetry.with_span', span_name: name, kind: kind)
      yield(nil) if block_given?
    end

    def record_exception(span, exception)
      return unless span.respond_to?(:record_exception)

      span.record_exception(exception)
      span.status = OpenTelemetry::Trace::Status.error(exception.message)
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.record_exception')
      nil
    end

    def sanitize_attributes(hash, max_keys: 20)
      return {} unless hash.is_a?(Hash)

      hash.first(max_keys).to_h do |k, v|
        val = case v
              when String, Integer, Float, TrueClass, FalseClass then v
              else v.to_s
              end
        [k.to_s, val]
      end
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.sanitize_attributes')
      {}
    end

    def configure_exporter
      backend = tracing_settings[:exporter]&.to_sym || :none

      case backend
      when :otlp
        configure_otlp
      when :console
        configure_console
      end
    end

    def tracing_settings
      telemetry = Legion::Settings[:telemetry]
      return {} unless telemetry.is_a?(Hash)

      tracing = telemetry[:tracing]
      tracing.is_a?(Hash) ? tracing : {}
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.tracing_settings')
      {}
    end

    def otel_init_error?(error)
      error.message.include?('OpenTelemetry') || error.message.include?('tracer')
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.otel_init_error?')
      false
    end

    def configure_otlp
      require 'opentelemetry-exporter-otlp'

      endpoint = tracing_settings[:endpoint] || 'http://localhost:4318/v1/traces'
      headers = tracing_settings[:headers] || {}

      exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: endpoint,
        headers:  headers
      )

      processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        exporter,
        max_queue_size:        2048,
        max_export_batch_size: tracing_settings[:batch_size] || 512
      )

      OpenTelemetry.tracer_provider.add_span_processor(processor)
      log.info "OTLP exporter configured: #{endpoint}"
      true
    rescue LoadError
      log.warn 'opentelemetry-exporter-otlp gem not available'
      false
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'telemetry.configure_otlp', endpoint: endpoint)
      false
    end

    def configure_console
      return false unless defined?(OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter)

      exporter = OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      OpenTelemetry.tracer_provider.add_span_processor(processor)
      log.info 'Console telemetry exporter configured'
      true
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'telemetry.configure_console')
      false
    end
  end
end
