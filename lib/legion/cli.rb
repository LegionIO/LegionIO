# frozen_string_literal: true

# require 'legion/cli/version'
require 'thor'
require 'legion'
require 'legion/service'

require 'legion/lex'
require 'legion/cli/cohort'

require 'legion/cli/relationship'
require 'legion/cli/task'
require 'legion/cli/chain'
require 'legion/cli/trigger'
require 'legion/cli/function'

module Legion
  class CLI < Thor
    include Thor::Actions

    check_unknown_options!

    def self.exit_on_failure?
      true
    end

    def self.source_root
      File.dirname(__FILE__)
    end

    desc 'version', 'Display MyGem version'
    map %w[-v --version] => :version

    def version
      say "Legion::CLI #{VERSION}"
    end

    desc 'lex', 'used to build LEXs'
    subcommand 'lex', Legion::Cli::LexBuilder

    desc 'cohort', ''
    subcommand 'cohort', Legion::Cli::Cohort

    desc 'function', 'deal with functions'
    subcommand 'function', Legion::Cli::Function

    desc 'relationship', 'creates and manages relationships'
    subcommand 'relationship', Legion::Cli::Relationship

    desc 'task', 'creates and manages tasks'
    subcommand 'task', Legion::Cli::Task

    desc 'chain', 'creates and manages chains'
    subcommand 'chain', Legion::Cli::Chain

    desc 'trigger', 'sends a task to a worker'
    subcommand 'trigger', Legion::Cli::Trigger
  end
end
