# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class CreateRelationship < ::MCP::Tool
        tool_name 'legion.create_relationship'
        description 'Create a new relationship between tasks/functions.'

        input_schema(
          properties: {
            trigger_function_id: { type: 'integer', description: 'Function ID that triggers this relationship' },
            target_function_id:  { type: 'integer', description: 'Function ID to be triggered' }
          },
          required:   %w[trigger_function_id target_function_id]
        )

        class << self
          def call(**attrs)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('relationship data model is not available') unless relationship_model?

            id = Legion::Data::Model::Relationship.insert(attrs)
            record = Legion::Data::Model::Relationship[id]
            text_response(record.values)
          rescue StandardError => e
            error_response("Failed to create relationship: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

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
