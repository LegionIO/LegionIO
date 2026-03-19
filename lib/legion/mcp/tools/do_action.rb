# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DoAction < ::MCP::Tool
        tool_name 'legion.do'
        description 'Execute a Legion action by describing what you want to do in natural language. Routes to the best matching tool automatically.'

        input_schema(
          properties: {
            intent: {
              type:        'string',
              description: 'Natural language description (e.g., "list all running tasks")'
            },
            params: {
              type:                 'object',
              description:          'Parameters to pass to the matched tool',
              additionalProperties: true
            }
          },
          required:   ['intent']
        )

        class << self
          def call(intent:, params: {})
            matched = ContextCompiler.match_tool(intent)
            return error_response("No matching tool found for intent: #{intent}") if matched.nil?

            Legion::MCP::Observer.record_intent(intent, matched) if defined?(Legion::MCP::Observer)

            tool_params = params.transform_keys(&:to_sym)
            if tool_params.empty?
              matched.call
            else
              matched.call(**tool_params)
            end
          rescue StandardError => e
            error_response("Failed: #{e.message}")
          end

          private

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
