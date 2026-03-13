# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class UpdateRelationship < ::MCP::Tool
        tool_name 'legion.update_relationship'
        description 'Update an existing relationship.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Relationship ID' },
            trigger_function_id: { type: 'integer', description: 'New trigger function ID' },
            target_function_id: { type: 'integer', description: 'New target function ID' }
          },
          required: ['id']
        )

        class << self
          def call(id:, **attrs)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('relationship data model is not available') unless relationship_model?

            record = Legion::Data::Model::Relationship[id.to_i]
            return error_response("Relationship #{id} not found") unless record

            record.update(attrs) unless attrs.empty?
            record.refresh
            text_response(record.values)
          rescue StandardError => e
            error_response("Failed to update relationship: #{e.message}")
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
