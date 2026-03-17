# frozen_string_literal: true

module Legion
  module Telemetry
    module_function

    def otel_available?
      defined?(OpenTelemetry::Trace) &&
        OpenTelemetry::Trace.current_span != OpenTelemetry::Trace::Span::INVALID
    rescue StandardError
      false
    end

    def enabled?
      defined?(OpenTelemetry::SDK) ? true : false
    rescue StandardError
      false
    end

    def with_span(name, kind: :internal, attributes: {}, &)
      unless enabled?
        return yield(nil) if block_given?

        return
      end

      tracer = OpenTelemetry.tracer_provider.tracer('legion', Legion::VERSION)
      tracer.in_span(name, kind: kind, attributes: sanitize_attributes(attributes), &)
    rescue StandardError => e
      raise if block_given? && !otel_init_error?(e)

      Legion::Logging.debug "[telemetry] span error: #{e.message}" if defined?(Legion::Logging)
      yield(nil) if block_given?
    end

    def record_exception(span, exception)
      return unless span.respond_to?(:record_exception)

      span.record_exception(exception)
      span.status = OpenTelemetry::Trace::Status.error(exception.message)
    rescue StandardError
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
    rescue StandardError
      {}
    end

    def otel_init_error?(error)
      error.message.include?('OpenTelemetry') || error.message.include?('tracer')
    rescue StandardError
      false
    end
  end
end
