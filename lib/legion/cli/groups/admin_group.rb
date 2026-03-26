# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Admin < Thor
        namespace 'admin'

        def self.exit_on_failure?
          true
        end

        desc 'rbac SUBCOMMAND', 'Role-based access control management'
        subcommand 'rbac', Legion::CLI::Rbac

        desc 'auth SUBCOMMAND', 'Authenticate with external services'
        subcommand 'auth', Legion::CLI::Auth

        desc 'worker SUBCOMMAND', 'Manage digital workers'
        subcommand 'worker', Legion::CLI::Worker

        desc 'team SUBCOMMAND', 'Team and multi-user management'
        subcommand 'team', Legion::CLI::Team
      end
    end
  end
end
