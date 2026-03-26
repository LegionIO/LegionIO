# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Dev < Thor
        namespace 'dev'

        def self.exit_on_failure?
          true
        end

        desc 'generate SUBCOMMAND', 'Code generators for LEX components'
        map 'g' => :generate
        subcommand 'generate', Legion::CLI::Generate

        desc 'docs SUBCOMMAND', 'Documentation site generator'
        subcommand 'docs', Legion::CLI::Docs

        desc 'openapi SUBCOMMAND', 'OpenAPI spec generation'
        subcommand 'openapi', Legion::CLI::Openapi

        desc 'completion SUBCOMMAND', 'Shell tab completion scripts'
        subcommand 'completion', Legion::CLI::Completion

        desc 'marketplace', 'Extension marketplace (search, info, scan)'
        subcommand 'marketplace', Legion::CLI::Marketplace

        desc 'features SUBCOMMAND', 'Install feature bundles (interactive selector)'
        subcommand 'features', Legion::CLI::Features
      end
    end
  end
end
