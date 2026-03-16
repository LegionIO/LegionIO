# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class RbacAssignments < ::MCP::Tool
        tool_name 'legion.rbac_assignments'
        description 'List RBAC role assignments. Filterable by team, role, or principal.'

        input_schema(
          properties: {
            team:      { type: 'string', description: 'Filter by team' },
            role:      { type: 'string', description: 'Filter by role name' },
            principal: { type: 'string', description: 'Filter by principal ID' }
          }
        )

        class << self
          def call(team: nil, role: nil, principal: nil)
            return error_response('legion-rbac not installed') unless defined?(Legion::Rbac)
            return error_response('legion-data not connected') unless Legion::Rbac::Store.db_available?

            ds = Legion::Data::Model::RbacRoleAssignment.dataset
            ds = ds.where(team: team) if team
            ds = ds.where(role: role) if role
            ds = ds.where(principal_id: principal) if principal
            text_response(ds.all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list assignments: #{e.message}")
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
