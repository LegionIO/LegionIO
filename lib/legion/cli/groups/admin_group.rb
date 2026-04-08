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

        desc 'purge-topology', 'Remove old v2.0 AMQP exchanges (legion.* that have lex.* counterparts)'
        method_option :dry_run,  type: :boolean, default: true,        desc: 'List without deleting'
        method_option :execute,  type: :boolean, default: false,       desc: 'Actually delete exchanges'
        method_option :host,     type: :string,  default: 'localhost', desc: 'RabbitMQ management host'
        method_option :port,     type: :numeric, default: 15_672,      desc: 'RabbitMQ management port'
        method_option :user,     type: :string,  default: 'guest',     desc: 'RabbitMQ management user'
        method_option :password, type: :string,  default: 'guest',     desc: 'RabbitMQ management password'
        method_option :vhost,    type: :string,  default: '/',         desc: 'RabbitMQ vhost'
        def purge_topology
          Legion::CLI::AdminCommand.new([], options).purge_topology
        end
      end
    end
  end
end
