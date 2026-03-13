# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DeleteTask < ::MCP::Tool
        tool_name 'legion.delete_task'
        description 'Delete a task by ID.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Task ID' }
          },
          required: ['id']
        )

        class << self
          def call(id:)
            return error_response('legion-data is not connected') unless data_connected?

            task = Legion::Data::Model::Task[id.to_i]
            return error_response("Task #{id} not found") unless task

            task.delete
            text_response({ deleted: true, id: id })
          rescue StandardError => e
            error_response("Failed to delete task: #{e.message}")
          end

          private

          def data_connected? = (Legion::Settings[:data][:connected] rescue false)

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
