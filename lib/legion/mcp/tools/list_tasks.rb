# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListTasks < ::MCP::Tool
        tool_name 'legion.list_tasks'
        description 'List recent tasks with optional filtering by status or function_id.'

        input_schema(
          properties: {
            status: { type: 'string', description: 'Filter by task status' },
            function_id: { type: 'integer', description: 'Filter by function ID' },
            limit: { type: 'integer', description: 'Max results (default 25, max 100)' }
          }
        )

        class << self
          def call(status: nil, function_id: nil, limit: 25)
            return error_response('legion-data is not connected') unless data_connected?

            limit = [[limit.to_i, 1].max, 100].min
            dataset = Legion::Data::Model::Task.order(Sequel.desc(:id))
            dataset = dataset.where(status: status) if status
            dataset = dataset.where(function_id: function_id.to_i) if function_id
            text_response(dataset.limit(limit).all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list tasks: #{e.message}")
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
