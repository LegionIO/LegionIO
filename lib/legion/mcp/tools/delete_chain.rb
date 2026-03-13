# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DeleteChain < ::MCP::Tool
        tool_name 'legion.delete_chain'
        description 'Delete a task chain by ID.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Chain ID' }
          },
          required:   ['id']
        )

        class << self
          def call(id:)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('chain data model is not available') unless chain_model?

            record = Legion::Data::Model::Chain[id.to_i]
            return error_response("Chain #{id} not found") unless record

            record.delete
            text_response({ deleted: true, id: id })
          rescue StandardError => e
            error_response("Failed to delete chain: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

          def chain_model? = Legion::Data::Model.const_defined?(:Chain)

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
