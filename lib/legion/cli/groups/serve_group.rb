# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Serve < Thor
        namespace 'serve'

        def self.exit_on_failure?
          true
        end

        desc 'mcp SUBCOMMAND', 'Start MCP server for AI agent integration'
        subcommand 'mcp', Legion::CLI::Mcp

        desc 'acp SUBCOMMAND', 'Start ACP agent for editor integration'
        subcommand 'acp', Legion::CLI::Acp
      end
    end
  end
end
