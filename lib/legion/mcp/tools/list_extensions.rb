# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListExtensions < ::MCP::Tool
        tool_name 'legion.list_extensions'
        description 'List all installed Legion extensions with status.'

        input_schema(
          properties: {
            active: { type: 'boolean', description: 'Filter by active status' }
          }
        )

        class << self
          def call(active: nil)
            return error_response('legion-data is not connected') unless data_connected?

            dataset = Legion::Data::Model::Extension.order(:id)
            dataset = dataset.where(active: true) if active == true
            text_response(dataset.all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list extensions: #{e.message}")
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
