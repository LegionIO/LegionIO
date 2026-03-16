# frozen_string_literal: true

module Legion
  module CLI
    class Rbac < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'roles', 'List role definitions from config'
      def roles
        out = formatter
        with_rbac do
          index = Legion::Rbac.role_index
          if options[:json]
            out.json(index.transform_values { |r| { description: r.description, cross_team: r.cross_team? } })
          else
            rows = index.map { |name, r| [name.to_s, r.description, r.cross_team? ? 'yes' : 'no'] }
            out.table(%w[Role Description CrossTeam], rows)
          end
        end
      end
      default_task :roles

      desc 'show ROLE', 'Show permissions for a role'
      def show(role_name)
        out = formatter
        with_rbac do
          role = Legion::Rbac.role_index[role_name.to_sym]
          unless role
            out.error("Role not found: #{role_name}")
            return
          end

          if options[:json]
            out.json({
                       name:        role.name,
                       description: role.description,
                       cross_team:  role.cross_team?,
                       permissions: role.permissions.map { |p| { resource: p.resource_pattern, actions: p.actions } },
                       deny_rules:  role.deny_rules.map { |d| { resource: d.resource_pattern, above_level: d.above_level } }
                     })
          else
            out.header("Role: #{role.name}")
            puts "  #{role.description}"
            puts "  Cross-team: #{role.cross_team? ? 'yes' : 'no'}"
            puts "\n  Permissions:"
            role.permissions.each { |p| puts "    #{p.resource_pattern} -> #{p.actions.join(', ')}" }
            puts "\n  Deny rules:"
            role.deny_rules.each { |d| puts "    #{d.resource_pattern}#{" (above level #{d.above_level})" if d.above_level}" }
          end
        end
      end

      desc 'assignments', 'List role assignments from DB'
      option :team, type: :string, desc: 'Filter by team'
      option :role, type: :string, desc: 'Filter by role'
      option :principal, type: :string, desc: 'Filter by principal ID'
      def assignments
        out = formatter
        with_data do
          ds = Legion::Data::Model::RbacRoleAssignment.dataset
          ds = ds.where(team: options[:team]) if options[:team]
          ds = ds.where(role: options[:role]) if options[:role]
          ds = ds.where(principal_id: options[:principal]) if options[:principal]

          records = ds.all
          if options[:json]
            out.json(records.map(&:values))
          else
            rows = records.map { |r| [r.id, r.principal_id, r.principal_type, r.role, r.team || '-', r.active? ? 'active' : 'expired'] }
            out.table(%w[ID Principal Type Role Team Status], rows)
          end
        end
      end

      desc 'assign PRINCIPAL ROLE', 'Assign a role to a principal'
      option :type, type: :string, default: 'human', desc: 'Principal type (human/worker)'
      option :team, type: :string, desc: 'Team scope'
      option :expires, type: :string, desc: 'Expiry (ISO 8601)'
      def assign(principal, role)
        out = formatter
        with_data do
          record = Legion::Data::Model::RbacRoleAssignment.create(
            principal_type: options[:type],
            principal_id:   principal,
            role:           role,
            team:           options[:team],
            granted_by:     'cli',
            expires_at:     options[:expires] ? Time.parse(options[:expires]) : nil
          )
          out.success("Assigned #{role} to #{principal} (id: #{record.id})")
        end
      end

      desc 'revoke PRINCIPAL ROLE', 'Remove a role assignment'
      def revoke(principal, role)
        out = formatter
        with_data do
          ds = Legion::Data::Model::RbacRoleAssignment.where(principal_id: principal, role: role)
          count = ds.count
          ds.destroy
          out.success("Revoked #{count} assignment(s) of #{role} from #{principal}")
        end
      end

      desc 'grants', 'List runner grants'
      option :team, type: :string, desc: 'Filter by team'
      def grants
        out = formatter
        with_data do
          ds = Legion::Data::Model::RbacRunnerGrant.dataset
          ds = ds.where(team: options[:team]) if options[:team]

          records = ds.all
          if options[:json]
            out.json(records.map(&:values))
          else
            rows = records.map { |r| [r.id, r.team, r.runner_pattern, r.actions] }
            out.table(%w[ID Team Pattern Actions], rows)
          end
        end
      end

      desc 'grant TEAM PATTERN', 'Grant runner access to a team'
      option :actions, type: :string, default: 'execute', desc: 'Comma-separated actions'
      def grant(team, pattern)
        out = formatter
        with_data do
          record = Legion::Data::Model::RbacRunnerGrant.create(
            team:           team,
            runner_pattern: pattern,
            actions:        options[:actions],
            granted_by:     'cli'
          )
          out.success("Granted #{pattern} to team #{team} (id: #{record.id})")
        end
      end

      desc 'check PRINCIPAL RESOURCE', 'Dry-run authorization check'
      option :action, type: :string, default: 'read', desc: 'Action to check'
      option :roles, type: :array, default: [], desc: 'Roles to check (comma-separated)'
      option :team, type: :string, desc: 'Team scope'
      def check(principal_id, resource)
        out = formatter
        with_rbac do
          principal = Legion::Rbac::Principal.new(
            id:    principal_id,
            roles: options[:roles],
            team:  options[:team]
          )
          result = Legion::Rbac::PolicyEngine.evaluate(
            principal: principal,
            action:    options[:action],
            resource:  resource,
            enforce:   false
          )
          if options[:json]
            out.json(result)
          else
            status = result[:allowed] ? 'ALLOWED' : 'DENIED'
            puts "  #{status}: #{principal_id} -> #{options[:action]} #{resource}"
            puts "  Reason: #{result[:reason]}" if result[:reason]
            puts "  Would deny: #{result[:would_deny]}" if result[:would_deny]
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        private

        def with_rbac
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_settings
          require 'legion/rbac'
          Legion::Rbac.setup
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        end

        def with_data
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_data
          require 'legion/rbac'
          Legion::Rbac.setup
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        ensure
          Connection.shutdown
        end
      end
    end
  end
end
