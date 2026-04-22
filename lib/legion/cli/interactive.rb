# frozen_string_literal: true

require 'thor'
require 'legion/version'
require 'legion/cli/error'
require 'legion/cli/output'

module Legion
  module CLI
    class Interactive < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'

      desc 'version', 'Show version information'
      map %w[-v --version] => :version
      def version
        Main.start(['version'] + ARGV.select { |a| a.start_with?('--') })
      end

      desc 'chat [SUBCOMMAND]', 'Text-based AI conversation'
      subcommand 'chat', Legion::CLI::Chat

      desc 'commit', 'Generate AI commit message from staged changes'
      subcommand 'commit', Legion::CLI::Commit

      desc 'pr', 'Create pull request with AI-generated title and description'
      subcommand 'pr', Legion::CLI::Pr

      desc 'review', 'AI code review of changes'
      subcommand 'review', Legion::CLI::Review

      desc 'memory SUBCOMMAND', 'Persistent project memory across sessions'
      subcommand 'memory', Legion::CLI::Memory

      desc 'plan', 'Start plan mode (read-only exploration, no writes)'
      subcommand 'plan', Legion::CLI::Plan

      desc 'init', 'Initialize a new Legion workspace'
      subcommand 'init', Legion::CLI::Init

      desc 'tty', 'Launch the rich terminal UI (alias for chat)'
      def tty(*args)
        Legion::CLI::Chat.start(['interactive'] + args + ARGV.select { |a| a.start_with?('--') })
      end

      desc 'ask TEXT', 'Quick AI prompt (shortcut for chat prompt)'
      map %w[-p --prompt] => :ask
      def ask(*text)
        Legion::CLI::Chat.start(['prompt', text.join(' ')] + ARGV.select { |a| a.start_with?('--') })
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
