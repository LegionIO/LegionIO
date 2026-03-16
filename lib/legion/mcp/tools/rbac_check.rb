# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class RbacCheck < ::MCP::Tool
        tool_name 'legion.rbac_check'
        description 'Dry-run authorization check. Evaluates RBAC policies without enforcing.'

        input_schema(
          properties: {
            principal: { type: 'string', description: 'Principal ID to check' },
            action:    { type: 'string', description: 'Action (read, execute, manage, etc.)' },
            resource:  { type: 'string', description: 'Resource path (e.g. runners/lex-github/*)' },
            roles:     { type: 'array', items: { type: 'string' }, description: 'Roles to evaluate' },
            team:      { type: 'string', description: 'Team scope' }
          },
          required:   %w[principal action resource roles]
        )

        class << self
          def call(principal:, action:, resource:, roles: [], team: nil)
            return error_response('legion-rbac not installed') unless defined?(Legion::Rbac)

            p = Legion::Rbac::Principal.new(id: principal, roles: roles, team: team)
            result = Legion::Rbac::PolicyEngine.evaluate(principal: p, action: action, resource: resource, enforce: false)
            text_response(result)
          rescue StandardError => e
            error_response("RBAC check failed: #{e.message}")
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
