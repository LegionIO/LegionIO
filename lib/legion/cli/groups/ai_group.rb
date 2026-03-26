# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Ai < Thor
        namespace 'ai'

        def self.exit_on_failure?
          true
        end

        desc 'chat SUBCOMMAND', 'Interactive AI conversation'
        subcommand 'chat', Legion::CLI::Chat

        desc 'llm SUBCOMMAND', 'LLM provider diagnostics (status, ping, models)'
        subcommand 'llm', Legion::CLI::Llm

        desc 'gaia SUBCOMMAND', 'GAIA cognitive coordination'
        subcommand 'gaia', Legion::CLI::Gaia

        desc 'apollo SUBCOMMAND', 'Apollo knowledge graph'
        subcommand 'apollo', Legion::CLI::Apollo

        desc 'knowledge SUBCOMMAND', 'Search and manage the document knowledge base'
        subcommand 'knowledge', Legion::CLI::Knowledge

        desc 'memory SUBCOMMAND', 'Persistent project memory across sessions'
        subcommand 'memory', Legion::CLI::Memory

        desc 'mind-growth SUBCOMMAND', 'Autonomous cognitive architecture expansion'
        subcommand 'mind-growth', Legion::CLI::MindGrowth

        desc 'swarm SUBCOMMAND', 'Multi-agent swarm orchestration'
        subcommand 'swarm', Legion::CLI::Swarm

        desc 'plan', 'Start plan mode (read-only exploration, no writes)'
        subcommand 'plan', Legion::CLI::Plan

        desc 'trace SUBCOMMAND', 'Natural language trace search via LLM'
        subcommand 'trace', Legion::CLI::TraceCommand
      end
    end
  end
end
