# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Git < Thor
        namespace 'git'

        def self.exit_on_failure?
          true
        end

        desc 'commit', 'Generate AI commit message from staged changes'
        subcommand 'commit', Legion::CLI::Commit

        desc 'pr', 'Create pull request with AI-generated title and description'
        subcommand 'pr', Legion::CLI::Pr

        desc 'review', 'AI code review of changes'
        subcommand 'review', Legion::CLI::Review
      end
    end
  end
end
