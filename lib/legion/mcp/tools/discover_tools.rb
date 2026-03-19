# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DiscoverTools < ::MCP::Tool
        tool_name 'legion.tools'
        description 'Discover available Legion tools by category or intent. Returns compressed definitions to reduce context.'

        input_schema(
          properties: {
            category: {
              type:        'string',
              description: 'Tool category: tasks, chains, relationships, extensions, schedules, workers, rbac, status, describe'
            },
            intent:   {
              type:        'string',
              description: 'Describe what you want to do and relevant tools will be ranked'
            }
          }
        )

        class << self
          def call(category: nil, intent: nil)
            if category
              result = ContextCompiler.category_tools(category.to_sym)
              return error_response("Unknown category: #{category}") if result.nil?

              text_response(result)
            elsif intent
              results = ContextCompiler.match_tools(intent, limit: 5)
              text_response({ matched_tools: results })
            else
              text_response(ContextCompiler.compressed_catalog)
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
