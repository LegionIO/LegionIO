# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetStatus < ::MCP::Tool
        tool_name 'legion.get_status'
        description 'Get Legion service health status and component info.'

        input_schema(properties: {})

        class << self
          def call
            status = {
              version:    Legion::VERSION,
              ready:      (Legion::Readiness.ready? rescue false),
              components: (Legion::Readiness.to_h rescue {}),
              node:       (Legion::Settings[:client][:name] rescue 'unknown')
            }
            text_response(status)
          rescue StandardError => e
            error_response("Failed to get status: #{e.message}")
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
