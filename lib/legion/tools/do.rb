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
        required:   ['intent']
      )

      class << self
        include Legion::Logging::Helper

        def call(intent:, params: {}, context: {})
          request_id = context[:request_id] || "do_#{SecureRandom.hex(6)}"
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
          if defined?(Legion::MCP::ContextCompiler)
            matched = Legion::MCP::ContextCompiler.match_tool(intent)
            return matched if matched
          end

          match_tool_from_registry(intent)
        rescue StandardError
          nil
        end

        def match_tool_from_registry(intent)
          return nil unless defined?(Legion::Tools::Registry)

          normalized = normalize_tool_text(intent)
          return nil if normalized.empty?

          tools = Legion::Tools::Registry.all_tools
          return nil if tools.empty?

          tools
            .map { |t| [t, score_tool_match(t, normalized)] }
            .select { |(_t, score)| score.positive? }
            .max_by { |(_t, score)| score }
            &.first
        rescue StandardError
          nil
        end

        def score_tool_match(tool, normalized_intent)
          name        = normalize_tool_text(tool.tool_name)
          description = normalize_tool_text(tool.respond_to?(:description) ? tool.description : nil)
          return 0 if name.empty? && description.empty?

          intent_terms = normalized_intent.split
          score        = 0
          score += 100 if !name.empty? && normalized_intent.include?(name)
          score += 50  if !description.empty? && normalized_intent.include?(description)
          score += (intent_terms & name.split).length * 10
          score += (intent_terms & description.split).length * 3
          score
        rescue StandardError
          0
        end

        def normalize_tool_text(text)
          text.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip
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
