# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Tty < Thor
      def self.exit_on_failure?
        true
      end

      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :config_dir, type: :string, desc: 'Config directory (~/.legionio/settings)'
      class_option :skip_rain, type: :boolean, default: false, desc: 'Skip the digital rain intro'

      default_task :interactive

      desc 'interactive', 'Launch the rich terminal UI (default)'
      long_desc <<~DESC
        Launches the Legion TTY - a rich terminal interface with:
        - Onboarding wizard (first run)
        - AI chat shell with streaming responses
        - Operational dashboard (Ctrl+D or /dashboard)
        - Session persistence across runs

        Similar to tools like Claude Code (CLI) and OpenAI Codex,
        but purpose-built for LegionIO's async cognition engine.

        First run: walks you through identity detection (Kerberos/GitHub),
        provider selection, and API key setup.

        Subsequent runs: loads saved identity, re-scans environment,
        and drops straight into the chat shell.
      DESC
      def interactive
        require_tty_gem
        config_dir = options[:config_dir] || Legion::TTY::App::CONFIG_DIR
        app = Legion::TTY::App.new(config_dir: config_dir)
        app.start
      rescue Interrupt
        app&.shutdown
      end

      desc 'reset', 'Clear saved identity and credentials (re-run onboarding)'
      option :confirm, type: :boolean, default: false, aliases: ['-y'], desc: 'Skip confirmation'
      def reset
        out = formatter
        config_dir = options[:config_dir] || File.expand_path('~/.legionio/settings')

        identity = File.join(config_dir, 'identity.json')
        credentials = File.join(config_dir, 'credentials.json')

        unless options[:confirm]
          out.warn('This will delete your saved identity and credentials.')
          out.warn('You will need to re-run onboarding.')
          require 'tty-prompt'
          prompt = ::TTY::Prompt.new
          return unless prompt.yes?('Continue?')
        end

        [identity, credentials].each do |path|
          if File.exist?(path)
            File.delete(path)
            out.success("Deleted #{File.basename(path)}")
          end
        end
      end

      desc 'sessions', 'List saved chat sessions'
      def sessions
        out = formatter
        require_tty_gem

        store = Legion::TTY::SessionStore.new
        list = store.list

        if list.empty?
          out.detail('No saved sessions.')
          return
        end

        list.each do |session|
          name = session[:name]
          count = session[:message_count]
          saved = session[:saved_at] || 'unknown'
          puts "  #{name.ljust(30)} #{count} messages  #{saved}"
        end
      end

      desc 'version', 'Show legion-tty version'
      def version
        require_tty_gem
        puts "legion-tty #{Legion::TTY::VERSION}"
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  false,
            color: !options[:no_color]
          )
        end

        private

        def require_tty_gem
          require 'legion/tty'
        rescue LoadError => e
          formatter.error("legion-tty gem not installed: #{e.message}")
          formatter.detail('Install with: gem install legion-tty')
          raise SystemExit, 1
        end
      end
    end
  end
end
