# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Ops < Thor
        namespace 'ops'

        def self.exit_on_failure?
          true
        end

        desc 'telemetry SUBCOMMAND', 'Session log analytics and telemetry'
        subcommand 'telemetry', Legion::CLI::Telemetry

        desc 'observe SUBCOMMAND', 'MCP tool observation stats'
        subcommand 'observe', Legion::CLI::ObserveCommand

        desc 'detect', 'Scan environment and recommend extensions'
        subcommand 'detect', Legion::CLI::Detect

        desc 'cost', 'Cost visibility and reporting'
        subcommand 'cost', Legion::CLI::Cost

        desc 'payroll SUBCOMMAND', 'Workforce cost and labor economics'
        subcommand 'payroll', Legion::CLI::Payroll

        desc 'audit SUBCOMMAND', 'Audit log inspection and verification'
        subcommand 'audit', Legion::CLI::Audit

        desc 'debug', 'Diagnostic dump for troubleshooting (pipe to LLM for analysis)'
        subcommand 'debug', Legion::CLI::Debug

        desc 'failover SUBCOMMAND', 'Region failover management'
        subcommand 'failover', Legion::CLI::Failover
      end
    end
  end
end
