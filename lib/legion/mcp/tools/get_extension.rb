# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetExtension < ::MCP::Tool
        tool_name 'legion.get_extension'
        description 'Get detailed info about an extension including its runners and functions.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Extension ID' }
          },
          required:   ['id']
        )

        class << self
          def call(id:)
            return error_response('legion-data is not connected') unless data_connected?

            ext = Legion::Data::Model::Extension[id.to_i]
            return error_response("Extension #{id} not found") unless ext

            runners = Legion::Data::Model::Runner.where(extension_id: id.to_i).all
            result = ext.values.merge(
              runners: runners.map do |r|
                functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
                r.values.merge(functions: functions.map(&:values))
              end
            )

            text_response(result)
          rescue StandardError => e
            error_response("Failed to get extension: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

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
