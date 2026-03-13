# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListRelationships < ::MCP::Tool
        tool_name 'legion.list_relationships'
        description 'List all task relationships.'

        input_schema(
          properties: {
            limit: { type: 'integer', description: 'Max results (default 25, max 100)' }
          }
        )

        class << self
          def call(limit: 25)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('relationship data model is not available') unless relationship_model?

            limit = [[limit.to_i, 1].max, 100].min
            text_response(Legion::Data::Model::Relationship.order(:id).limit(limit).all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list relationships: #{e.message}")
          end

          private

          def data_connected? = (Legion::Settings[:data][:connected] rescue false)
          def relationship_model? = Legion::Data::Model.const_defined?(:Relationship)

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
