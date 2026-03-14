# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class RoutingStats < ::MCP::Tool
        tool_name 'legion.routing_stats'
        description 'Retrieve LLM routing statistics: breakdown by provider, model, and routing reason. Requires lex-metering.'

        input_schema(
          properties: {
            worker_id: { type: 'string', description: 'Optional: filter stats to a specific worker UUID' }
          }
        )

        class << self
          def call(worker_id: nil)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('lex-metering is not loaded') unless metering_available?

            runner = Object.new.extend(Legion::Extensions::Metering::Runners::Metering)
            stats = runner.routing_stats(worker_id: worker_id)
            text_response(stats)
          rescue StandardError => e
            error_response("Failed to fetch routing stats: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

          def metering_available?
            defined?(Legion::Extensions::Metering::Runners::Metering)
          end

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
