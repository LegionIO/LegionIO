# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListSchedules < ::MCP::Tool
        tool_name 'legion.list_schedules'
        description 'List all schedules. Requires lex-scheduler.'

        input_schema(
          properties: {
            active: { type: 'boolean', description: 'Filter by active status' },
            limit:  { type: 'integer', description: 'Max results (default 25, max 100)' }
          }
        )

        class << self
          def call(active: nil, limit: 25)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('lex-scheduler is not loaded') unless scheduler_loaded?

            limit = limit.to_i.clamp(1, 100)
            dataset = Legion::Extensions::Scheduler::Data::Model::Schedule.order(:id)
            dataset = dataset.where(active: true) if active == true
            text_response(dataset.limit(limit).all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list schedules: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

          def scheduler_loaded? = defined?(Legion::Extensions::Scheduler)

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
