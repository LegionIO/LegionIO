# frozen_string_literal: true

require 'securerandom'

module Legion
  module Tools
    class Do < Base
      tool_name 'legion.do'
      description 'Execute a Legion action by describing what you want to do in natural language. ' \
                  'Routes to the best matching tool automatically.'
      input_schema(
        properties: {
          intent:  {
            type:        'string',
            description: 'Natural language description (e.g., "list all running tasks")'
          },
          params:  {
            type:                 'object',
            description:          'Parameters to pass to the matched tool',
            additionalProperties: true
          },
          context: {
            type:                 'object',
            description:          'Additional context (service, environment, etc.)',
            additionalProperties: true
          }
        },
        required: ['intent']
      )

      class << self
        def call(intent:, params: {}, context: {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          request_id = context.dig(:request_id) || "do_#{SecureRandom.hex(6)}"
          tool_params = params.transform_keys(&:to_sym)

          # Try Tier 0 (cached patterns) if MCP TierRouter is available
          tier_result = try_tier0(intent, tool_params, context, request_id: request_id)
          case tier_result&.dig(:tier)
          when 0
            return text_response(tier_result[:response].merge(
                                   _meta: { tier: 0, latency_ms: tier_result[:latency_ms],
                                            confidence: tier_result[:pattern_confidence] }
                                 ))
          when 1
            llm_result = try_llm(intent, hint: tier_result[:pattern], request_id: request_id)
            return text_response({ result: llm_result, _meta: { tier: 1 } }) if llm_result
          when 2
            llm_result = try_llm(intent, request_id: request_id)
            return text_response({ result: llm_result, _meta: { tier: 2 } }) if llm_result
          end

          # Fall back to Registry tool matching
          matched = match_tool(intent)
          return error_response("No matching tool found for intent: #{intent}") if matched.nil?

          result = tool_params.empty? ? matched.call : matched.call(**tool_params)
          record_feedback(intent, matched.tool_name, success: true)
          result.is_a?(Hash) ? result : text_response(result)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :tool_do_call)
          error_response("Failed: #{e.message}")
        end

        private

        def match_tool(intent)
          return nil unless defined?(Legion::MCP::ContextCompiler)

          Legion::MCP::ContextCompiler.match_tool(intent)
        rescue StandardError
          nil
        end

        def try_tier0(intent, params, context, request_id: nil)
          return nil unless defined?(Legion::MCP::TierRouter)

          Legion::MCP::TierRouter.route(
            intent: intent, params: params.transform_keys(&:to_sym),
            context: context.to_h.transform_keys(&:to_sym).merge(request_id: request_id)
          )
        rescue StandardError
          nil
        end

        def try_llm(intent, hint: nil, request_id: nil)
          return nil unless defined?(Legion::LLM) && Legion::LLM.started?

          prompt = hint ? "Known pattern: #{hint[:intent_text]}. User intent: #{intent}" : intent
          Legion::LLM.ask(
            prompt,
            caller: { extension: 'legionio', tool: 'do', request_id: request_id }
          )
        rescue StandardError
          nil
        end

        def record_feedback(intent, tool_name, success:)
          return unless defined?(Legion::MCP::Observer)

          Legion::MCP::Observer.record_intent_with_result(
            intent: intent, tool_name: tool_name, success: success
          )
        rescue StandardError
          nil
        end
      end

      Legion::Tools.register_class(self)
    end
  end
end
