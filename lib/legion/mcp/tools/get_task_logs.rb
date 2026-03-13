# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetTaskLogs < ::MCP::Tool
        tool_name 'legion.get_task_logs'
        description 'Get execution logs for a specific task.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Task ID' },
            limit: { type: 'integer', description: 'Max log entries (default 50)' }
          },
          required: ['id']
        )

        class << self
          def call(id:, limit: 50)
            return error_response('legion-data is not connected') unless data_connected?

            task = Legion::Data::Model::Task[id.to_i]
            return error_response("Task #{id} not found") unless task

            limit = [[limit.to_i, 1].max, 100].min
            logs = Legion::Data::Model::TaskLog
                   .where(task_id: id.to_i)
                   .order(Sequel.desc(:id))
                   .limit(limit)
                   .all.map(&:values)

            text_response(logs)
          rescue StandardError => e
            error_response("Failed to get task logs: #{e.message}")
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
