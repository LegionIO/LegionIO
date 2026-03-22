# frozen_string_literal: true

module Legion
  module Telemetry
    autoload :OpenInference, 'legion/telemetry/open_inference'
    autoload :SafetyMetrics, 'legion/telemetry/safety_metrics'

    module_function

    def otel_available?
      defined?(OpenTelemetry::Trace) &&
        OpenTelemetry::Trace.current_span != OpenTelemetry::Trace::Span::INVALID
    rescue StandardError => e
      Legion::Logging.debug "Telemetry#otel_available? failed: #{e.message}" if defined?(Legion::Logging)
      false
    end

    def enabled?
      defined?(OpenTelemetry::SDK) ? true : false
    rescue StandardError => e
      Legion::Logging.debug "Telemetry#enabled? failed: #{e.message}" if defined?(Legion::Logging)
      false
    end

    def with_span(name, kind: :internal, attributes: {}, &)
      unless enabled?
        return yield(nil) if block_given?

        return
      end

      Legion::Logging.debug "[Telemetry] span: #{name}" if defined?(Legion::Logging)
      tracer = OpenTelemetry.tracer_provider.tracer('legion', Legion::VERSION)
      tracer.in_span(name, kind: kind, attributes: sanitize_attributes(attributes), &)
    rescue StandardError => e
      raise if block_given? && !otel_init_error?(e)

      Legion::Logging.debug "[Telemetry] span error for #{name}: #{e.message}" if defined?(Legion::Logging)
      yield(nil) if block_given?
    end

    def record_exception(span, exception)
      return unless span.respond_to?(:record_exception)

      span.record_exception(exception)
      span.status = OpenTelemetry::Trace::Status.error(exception.message)
    rescue StandardError => e
      Legion::Logging.debug "Telemetry#record_exception failed: #{e.message}" if defined?(Legion::Logging)
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
      Legion::Logging.debug "Telemetry#sanitize_attributes failed: #{e.message}" if defined?(Legion::Logging)
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
      Legion::Logging.debug "Telemetry#tracing_settings failed: #{e.message}" if defined?(Legion::Logging)
      {}
    end

    def otel_init_error?(error)
      error.message.include?('OpenTelemetry') || error.message.include?('tracer')
    rescue StandardError => e
      Legion::Logging.debug "Telemetry#otel_init_error? check failed: #{e.message}" if defined?(Legion::Logging)
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
      Legion::Logging.info "OTLP exporter configured: #{endpoint}"
      true
    rescue LoadError
      Legion::Logging.warn 'opentelemetry-exporter-otlp gem not available'
      false
    end

    def configure_console
      return false unless defined?(OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter)

      exporter = OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      OpenTelemetry.tracer_provider.add_span_processor(processor)
      true
    rescue StandardError => e
      Legion::Logging.debug "Telemetry#configure_console failed: #{e.message}" if defined?(Legion::Logging)
      false
    end
  end
end
