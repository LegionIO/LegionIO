# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class RbacGrants < ::MCP::Tool
        tool_name 'legion.rbac_grants'
        description 'List RBAC runner grants. Filterable by team.'

        input_schema(
          properties: {
            team: { type: 'string', description: 'Filter by team' }
          }
        )

        class << self
          def call(team: nil)
            return error_response('legion-rbac not installed') unless defined?(Legion::Rbac)
            return error_response('legion-data not connected') unless Legion::Rbac::Store.db_available?

            ds = Legion::Data::Model::RbacRunnerGrant.dataset
            ds = ds.where(team: team) if team
            text_response(ds.all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list grants: #{e.message}")
          end

          private

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
