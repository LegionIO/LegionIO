# frozen_string_literal: true

require 'thor'
require 'legion/version'
require 'legion/cli/error'
require 'legion/cli/output'
require 'legion/cli/connection'

module Legion
  module CLI
    autoload :Start,    'legion/cli/start'
    autoload :Status,   'legion/cli/status'
    autoload :Lex,      'legion/cli/lex_command'
    autoload :Task,     'legion/cli/task_command'
    autoload :Chain,    'legion/cli/chain_command'
    autoload :Config,   'legion/cli/config_command'
    autoload :Generate, 'legion/cli/generate_command'
    autoload :Check,    'legion/cli/check_command'
    autoload :Mcp,      'legion/cli/mcp_command'
    autoload :Worker,    'legion/cli/worker_command'
    autoload :Coldstart, 'legion/cli/coldstart_command'
    autoload :Chat,      'legion/cli/chat_command'
    autoload :Commit,    'legion/cli/commit_command'
    autoload :Pr,        'legion/cli/pr_command'
    autoload :Review,    'legion/cli/review_command'
    autoload :Memory,    'legion/cli/memory_command'
    autoload :Plan,      'legion/cli/plan_command'
    autoload :Swarm,     'legion/cli/swarm_command'
    autoload :Gaia,       'legion/cli/gaia_command'
    autoload :Schedule,   'legion/cli/schedule_command'
    autoload :Completion, 'legion/cli/completion_command'
    autoload :Openapi,    'legion/cli/openapi_command'
    autoload :Doctor,     'legion/cli/doctor_command'
    autoload :Telemetry,  'legion/cli/telemetry_command'

    class Main < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'version', 'Show version information'
      map %w[-v --version] => :version
      def version
        out = formatter
        if options[:json]
          out.json(version: Legion::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM)
        else
          out.banner(version: Legion::VERSION)
          out.spacer
          out.detail({ ruby: RUBY_VERSION, platform: RUBY_PLATFORM })
          out.spacer

          installed = installed_components
          out.header('Components')
          installed.each do |name, ver|
            puts "  #{out.colorize(name.to_s.ljust(20), :label)} #{ver}"
          end

          out.spacer
          lex_count = discovered_lexs.size
          puts "  #{out.colorize("#{lex_count} extension(s)", :accent)} installed"
        end
      end

      desc 'start', 'Start the Legion daemon'
      long_desc <<~DESC
        Starts the full Legion service including transport, data, extensions,
        and the HTTP API. Supports daemonization and PID management.
      DESC
      option :daemonize, type: :boolean, default: false, aliases: ['-d'], desc: 'Run as background daemon'
      option :pidfile, type: :string, aliases: ['-p'], desc: 'PID file path'
      option :logfile, type: :string, aliases: ['-l'], desc: 'Log file path'
      option :time_limit, type: :numeric, aliases: ['-t'], desc: 'Run for N seconds then exit'
      option :log_level, type: :string, default: 'info', desc: 'Log level (debug, info, warn, error)'
      option :api, type: :boolean, default: true, desc: 'Start the HTTP API server'
      def start
        Legion::CLI::Start.run(options)
      end

      desc 'stop', 'Stop a running Legion daemon'
      option :pidfile, type: :string, aliases: ['-p'], desc: 'PID file path'
      option :signal, type: :string, default: 'INT', desc: 'Signal to send (INT, TERM)'
      def stop
        out = formatter
        pidfile = options[:pidfile] || find_pidfile
        unless pidfile && File.exist?(pidfile)
          out.error('No PID file found. Is Legion running?')
          raise SystemExit, 1
        end

        pid = File.read(pidfile).to_i
        sig = options[:signal].upcase
        Process.kill(sig, pid)
        out.success("Sent #{sig} to Legion process #{pid}")
      rescue Errno::ESRCH
        out.warn("Process #{pid} not found (already stopped?)")
        FileUtils.rm_f(pidfile)
      rescue Errno::EPERM
        out.error("Permission denied sending signal to process #{pid}")
        raise SystemExit, 1
      end

      desc 'status', 'Show running service status'
      def status
        Legion::CLI::Status.run(formatter, options)
      end

      desc 'check', 'Verify Legion can start successfully'
      long_desc <<~DESC
        Smoke-test Legion subsystem connectivity. Tries each subsystem,
        reports pass/fail, then shuts down.

        Default: check settings, crypt, transport, cache, data connections.
        --extensions: also load and wire up all LEX gems.
        --full: full boot cycle including API server.
      DESC
      option :extensions, type: :boolean, default: false, desc: 'Also load extensions'
      option :full, type: :boolean, default: false, desc: 'Full boot cycle (extensions + API)'
      def check
        exit_code = Legion::CLI::Check.run(formatter, options)
        exit(exit_code) if exit_code != 0
      end

      desc 'lex SUBCOMMAND', 'Manage Legion extensions (LEXs)'
      subcommand 'lex', Legion::CLI::Lex

      desc 'task SUBCOMMAND', 'Manage tasks'
      subcommand 'task', Legion::CLI::Task

      desc 'chain SUBCOMMAND', 'Manage task chains'
      subcommand 'chain', Legion::CLI::Chain

      desc 'config SUBCOMMAND', 'View and validate configuration'
      subcommand 'config', Legion::CLI::Config

      desc 'generate SUBCOMMAND', 'Code generators for LEX components'
      map 'g' => :generate
      subcommand 'generate', Legion::CLI::Generate

      desc 'mcp SUBCOMMAND', 'Start MCP server for AI agent integration'
      subcommand 'mcp', Legion::CLI::Mcp

      desc 'worker SUBCOMMAND', 'Manage digital workers'
      subcommand 'worker', Legion::CLI::Worker

      desc 'coldstart SUBCOMMAND', 'Cold start bootstrap and Claude memory ingestion'
      subcommand 'coldstart', Legion::CLI::Coldstart

      desc 'chat SUBCOMMAND', 'Interactive AI conversation'
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

      desc 'swarm SUBCOMMAND', 'Multi-agent swarm orchestration'
      subcommand 'swarm', Legion::CLI::Swarm

      desc 'gaia SUBCOMMAND', 'GAIA cognitive coordination'
      subcommand 'gaia', Legion::CLI::Gaia

      desc 'schedule SUBCOMMAND', 'Manage schedules'
      subcommand 'schedule', Legion::CLI::Schedule

      desc 'completion SUBCOMMAND', 'Shell tab completion scripts'
      subcommand 'completion', Legion::CLI::Completion

      desc 'openapi SUBCOMMAND', 'OpenAPI spec generation'
      subcommand 'openapi', Legion::CLI::Openapi

      desc 'doctor', 'Diagnose environment and suggest fixes'
      subcommand 'doctor', Legion::CLI::Doctor

      desc 'telemetry SUBCOMMAND', 'Session log analytics and telemetry'
      subcommand 'telemetry', Legion::CLI::Telemetry

      desc 'tree', 'Print a tree of all available commands'
      def tree
        legion_print_command_tree(self.class, 'legion', '')
      end

      desc 'ask TEXT', 'Quick AI prompt (shortcut for chat prompt)'
      map %w[-p --prompt] => :ask
      def ask(*text)
        Legion::CLI::Chat.start(['prompt', text.join(' ')] + ARGV.select { |a| a.start_with?('--') })
      end

      desc 'dream', 'Trigger a dream cycle on the running daemon'
      option :wait, type: :boolean, default: false, desc: 'Wait for dream cycle to complete'
      def dream
        out = formatter
        require 'net/http'
        require 'json'
        port = api_port
        uri = URI("http://localhost:#{port}/api/tasks")
        body = ::JSON.generate({
                                 runner_class:  'Legion::Extensions::Dream::Runners::DreamCycle',
                                 function:      'execute_dream_cycle',
                                 async:         !options[:wait],
                                 check_subtask: false,
                                 generate_task: false
                               })

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = options[:wait] ? 300 : 5
        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = body

        response = http.request(request)
        parsed = ::JSON.parse(response.body, symbolize_names: true)

        if options[:json]
          out.json(parsed)
        elsif response.is_a?(Net::HTTPSuccess)
          out.success('Dream cycle triggered on daemon')
          out.detail(parsed[:data] || parsed) if parsed[:data]
        else
          out.error("Dream cycle failed: #{parsed.dig(:error, :message) || response.code}")
        end
      rescue Net::ReadTimeout
        out.success('Dream cycle triggered on daemon (running in background)')
      rescue Errno::ECONNREFUSED
        out.error(format('Daemon not running (connection refused on port %d)', port))
        raise SystemExit, 1
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_connection
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
        end

        private

        def installed_components
          components = { legionio: Legion::VERSION }
          %w[legion-transport legion-data legion-cache legion-crypt legion-json legion-logging legion-settings].each do |gem_name|
            spec = Gem::Specification.find_by_name(gem_name)
            short = gem_name.sub('legion-', '')
            components[short.to_sym] = spec.version.to_s
          rescue Gem::MissingSpecError
            components[gem_name.sub('legion-', '').to_sym] = '(not installed)'
          end
          components
        end

        def discovered_lexs
          Gem::Specification.all_names.select { |g| g.start_with?('lex-') }
        end

        def find_pidfile
          %w[/var/run/legion.pid /tmp/legion.pid].find { |f| File.exist?(f) }
        end

        def api_port
          require 'legion/settings'
          Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
          api_settings = Legion::Settings[:api]
          (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
        rescue StandardError
          4567
        end

        def legion_print_command_tree(klass, label, indent)
          say "#{indent}#{label}", :blue

          child_indent = "#{indent}  "
          visible_commands = klass.commands.reject { |_, cmd| cmd.hidden? || cmd.name == 'help' || cmd.name == 'tree' }
          last_command_idx = visible_commands.count - 1
          has_subcommands = klass.subcommand_classes.any?
          visible_commands.sort.each_with_index do |(command_name, command), i|
            description = command.description.split("\n").first || ''
            icon = i == last_command_idx && !has_subcommands ? "\u2514\u2500" : "\u251c\u2500"
            say "#{child_indent}#{icon} ", nil, false
            say command_name, :green, false
            say " (#{description})" unless description.empty?
          end

          klass.subcommand_classes.each do |subcommand_name, subclass|
            legion_print_command_tree(subclass, "#{label} #{subcommand_name}", child_indent)
          end
        end
      end
    end
  end
end
