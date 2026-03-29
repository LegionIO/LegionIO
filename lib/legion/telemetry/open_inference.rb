# frozen_string_literal: true

module Legion
  module Telemetry
    module OpenInference
      DEFAULT_TRUNCATE = 4096

      module_function

      def open_inference_enabled?
        return false unless Legion::Telemetry.enabled?

        settings = begin
          Legion::Settings.dig(:telemetry, :open_inference)
        rescue StandardError => e
          Legion::Logging.debug "OpenInference#open_inference_enabled? failed to read settings: #{e.message}" if defined?(Legion::Logging)
          {}
        end
        settings.is_a?(Hash) ? settings.fetch(:enabled, true) : true
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#open_inference_enabled? failed: #{e.message}" if defined?(Legion::Logging)
        false
      end

      def include_io?
        settings = begin
          Legion::Settings.dig(:telemetry, :open_inference)
        rescue StandardError => e
          Legion::Logging.debug "OpenInference#include_io? failed to read settings: #{e.message}" if defined?(Legion::Logging)
          {}
        end
        settings.is_a?(Hash) ? settings.fetch(:include_input_output, true) : true
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#include_io? failed: #{e.message}" if defined?(Legion::Logging)
        true
      end

      def truncate_limit
        settings = begin
          Legion::Settings.dig(:telemetry, :open_inference)
        rescue StandardError => e
          Legion::Logging.debug "OpenInference#truncate_limit failed to read settings: #{e.message}" if defined?(Legion::Logging)
          {}
        end
        settings.is_a?(Hash) ? settings.fetch(:truncate_values_at, DEFAULT_TRUNCATE) : DEFAULT_TRUNCATE
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#truncate_limit failed: #{e.message}" if defined?(Legion::Logging)
        DEFAULT_TRUNCATE
      end

      def llm_span(model:, provider: nil, invocation_params: {}, input: nil)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('LLM').merge('llm.model_name' => model)
        attrs['llm.provider'] = provider if provider
        attrs['llm.invocation_parameters'] = invocation_params.to_json unless invocation_params.empty?
        attrs['input.value'] = truncate_value(input.to_s) if input && include_io?

        Legion::Telemetry.with_span("llm.#{model}", kind: :client, attributes: attrs) do |span|
          result = yield(span)
          annotate_llm_result(span, result) if span
          result
        end
      end

      def embedding_span(model:, dimensions: nil, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('EMBEDDING').merge('embedding.model_name' => model)
        attrs['embedding.dimensions'] = dimensions if dimensions

        Legion::Telemetry.with_span("embedding.#{model}", kind: :client, attributes: attrs, &)
      end

      def tool_span(name:, parameters: {})
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('TOOL').merge('tool.name' => name)
        attrs['tool.parameters'] = parameters.to_json unless parameters.empty?

        Legion::Telemetry.with_span("tool.#{name}", kind: :internal, attributes: attrs) do |span|
          result = yield(span)
          annotate_output(span, result) if span && include_io?
          result
        end
      end

      def chain_span(type: 'task_chain', relationship_id: nil, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('CHAIN').merge('chain.type' => type)
        attrs['chain.relationship_id'] = relationship_id if relationship_id

        Legion::Telemetry.with_span("chain.#{type}", kind: :internal, attributes: attrs, &)
      end

      def evaluator_span(template:)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('EVALUATOR').merge('eval.template' => template)

        Legion::Telemetry.with_span("eval.#{template}", kind: :internal, attributes: attrs) do |span|
          result = yield(span)
          annotate_eval_result(span, result) if span && result.is_a?(Hash)
          result
        end
      end

      def agent_span(name:, mode: nil, phase_count: nil, budget_ms: nil, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('AGENT').merge('agent.name' => name)
        attrs['agent.mode'] = mode.to_s if mode
        attrs['agent.phase_count'] = phase_count if phase_count
        attrs['agent.budget_ms'] = budget_ms if budget_ms

        Legion::Telemetry.with_span("agent.#{name}", kind: :internal, attributes: attrs, &)
      end

      def retriever_span(query:, limit: nil, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('RETRIEVER').merge('retriever.query' => truncate_value(query.to_s))
        attrs['retriever.limit'] = limit if limit

        Legion::Telemetry.with_span('retriever', kind: :internal, attributes: attrs, &)
      end

      def reranker_span(query:, model: nil, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('RERANKER').merge('reranker.query' => truncate_value(query.to_s))
        attrs['reranker.model_name'] = model if model

        Legion::Telemetry.with_span('reranker', kind: :internal, attributes: attrs, &)
      end

      def guardrail_span(name:, &)
        unless open_inference_enabled?
          return yield(nil) if block_given?

          return
        end

        attrs = base_attrs('GUARDRAIL').merge('guardrail.name' => name)

        Legion::Telemetry.with_span("guardrail.#{name}", kind: :internal, attributes: attrs, &)
      end

      def truncate_value(str, max: nil)
        limit = max || truncate_limit
        str.length > limit ? str[0...limit] : str
      end

      def base_attrs(kind)
        { 'openinference.span.kind' => kind }
      end

      def annotate_llm_result(span, result)
        return unless span.respond_to?(:set_attribute) && result.is_a?(Hash)

        span.set_attribute('llm.token_count.prompt', result[:input_tokens]) if result[:input_tokens]
        span.set_attribute('llm.token_count.completion', result[:output_tokens]) if result[:output_tokens]
        span.set_attribute('output.value', truncate_value(result[:content].to_s)) if include_io? && result[:content]
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#annotate_llm_result failed: #{e.message}" if defined?(Legion::Logging)
        nil
      end

      def annotate_output(span, result)
        return unless span.respond_to?(:set_attribute)

        val = result.is_a?(Hash) ? result.to_json : result.to_s
        span.set_attribute('output.value', truncate_value(val))
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#annotate_output failed: #{e.message}" if defined?(Legion::Logging)
        nil
      end

      def annotate_eval_result(span, result)
        return unless span.respond_to?(:set_attribute)

        span.set_attribute('eval.score', result[:score]) if result[:score]
        span.set_attribute('eval.passed', result[:passed]) unless result[:passed].nil?
        span.set_attribute('eval.explanation', result[:explanation]) if result[:explanation]
      rescue StandardError => e
        Legion::Logging.debug "OpenInference#annotate_eval_result failed: #{e.message}" if defined?(Legion::Logging)
        nil
      end
    end
  end
end
