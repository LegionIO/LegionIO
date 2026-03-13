# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DeleteSchedule < ::MCP::Tool
        tool_name 'legion.delete_schedule'
        description 'Delete a schedule by ID.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Schedule ID' }
          },
          required: ['id']
        )

        class << self
          def call(id:)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('lex-scheduler is not loaded') unless scheduler_loaded?

            record = Legion::Extensions::Scheduler::Data::Model::Schedule[id.to_i]
            return error_response("Schedule #{id} not found") unless record

            record.delete
            text_response({ deleted: true, id: id })
          rescue StandardError => e
            error_response("Failed to delete schedule: #{e.message}")
          end

          private

          def data_connected? = (Legion::Settings[:data][:connected] rescue false)
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
