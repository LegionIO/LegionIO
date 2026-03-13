# frozen_string_literal: true

require 'thor'
require 'legion/cli/version'
require 'legion/cli/lex/actor'
require 'legion/cli/lex/exchange'
require 'legion/cli/lex/message'
require 'legion/cli/lex/queue'
require 'legion/cli/lex/runner'

module Legion
  class Cli
    class LexBuilder < Thor
      check_unknown_options!
      include Thor::Actions

      no_commands do
        def lex
          Dir.pwd.split('/').last.split('-').last
        end
      end

      def self.exit_on_failure?
        true
      end

      def self.source_root
        File.dirname(__FILE__)
      end

      desc 'actor', 'creates and manages actors'
      subcommand 'actor', Legion::Cli::Lex::Actor

      desc 'exchange', 'creates and manages exchanges'
      subcommand 'exchange', Legion::Cli::Lex::Exchange

      desc 'messages', 'creates and manages messages'
      subcommand 'message',  Legion::Cli::Lex::Message

      desc 'queue', 'creates and manages queues'
      subcommand 'queue', Legion::Cli::Lex::Queue

      desc 'runner', 'creates and manages runners'
      subcommand 'runner', Legion::Cli::Lex::Runner

      desc 'version', 'Display Version'
      map %w[-v --version] => :version
      def version
        say "Legion::CLI #{Legion::Cli::VERSION}"
      end

      method_option rspec: true
      method_option pipeline: true
      method_option git_init: true
      method_option bundle_install: true
      desc 'create :name', 'creates a new lex'
      def create(name)
        if Dir.pwd.include?('lex-')
          say('already inside a lex_gen, try moving to a different directory', :red)
          return nil
        end

        vars = { filename: "lex-#{name}", class_name: name.capitalize, lex: name }
        filename = vars[:filename]
        template('cli/lex/templates/base/gemspec.erb', "#{filename}/#{filename}.gemspec", vars)
        template('cli/lex/templates/base/gemfile.erb', "#{filename}/Gemfile", vars)
        template('cli/lex/templates/base/gitignore.erb', "#{filename}/.gitignore", vars)
        template('cli/lex/templates/base/lic.erb', "#{filename}/LICENSE", vars)
        template('cli/lex/templates/base/rubocop.yml.erb', "#{filename}/.rubocop.yml", vars)
        template('cli/lex/templates/base/readme.md.erb', "#{filename}/README.md", **vars)
        template('cli/lex/templates/base/lex.erb', "#{filename}/lib/legion/extensions/#{name}.rb", vars)
        template('cli/lex/templates/base/version.erb', "#{filename}/lib/legion/extensions/#{name}/version.rb", vars)
        template('cli/lex/templates/base/spec_helper.rb.erb', "#{filename}/spec/spec_helper.rb", vars)
        template('cli/lex/templates/base/lex_spec.erb', "#{filename}/spec/legion/#{name}_spec.rb", vars)

        template('cli/lex/templates/base/github_rspec.yml.erb', "#{filename}/.github/workflows/rspec.yml", vars)
        template('cli/lex/templates/base/github_rubocop.yml.erb', "#{filename}/.github/workflows/rubocop.yml", vars)

        return if !options[:git_init] && !options[:bundle_install]

        run("cd lex_gen-#{filename}")
        if options[:git_init]
          run('git init')
          run('git add .')
          run('git commit -m \'Initial commit\'')
        end

        run('bundle update') if options[:bundle_install]
      end
    end
  end
end
