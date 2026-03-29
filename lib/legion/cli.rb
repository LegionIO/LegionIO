# frozen_string_literal: true

require 'thor'
require 'legion/version'
require 'legion/cli/error'
require 'legion/cli/error_handler'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error_forwarder'

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
    autoload :Memory,      'legion/cli/memory_command'
    autoload :MindGrowth,  'legion/cli/mind_growth_command'
    autoload :Plan,      'legion/cli/plan_command'
    autoload :Swarm,     'legion/cli/swarm_command'
    autoload :Gaia,       'legion/cli/gaia_command'
    autoload :Schedule,   'legion/cli/schedule_command'
    autoload :Completion, 'legion/cli/completion_command'
    autoload :Openapi,    'legion/cli/openapi_command'
    autoload :Doctor,     'legion/cli/doctor_command'
    autoload :Telemetry,  'legion/cli/telemetry_command'
    autoload :Auth,       'legion/cli/auth_command'
    autoload :Rbac,       'legion/cli/rbac_command'
    autoload :Acp,        'legion/cli/acp_command'
    autoload :Audit,      'legion/cli/audit_command'
    autoload :Detect,     'legion/cli/detect_command'
    autoload :Eval,       'legion/cli/eval_command'
    autoload :Update,     'legion/cli/update_command'
    autoload :Init,       'legion/cli/init_command'
    autoload :Knowledge,  'legion/cli/knowledge_command'
    autoload :Setup,      'legion/cli/setup_command'
    autoload :Skill,      'legion/cli/skill_command'
    autoload :Prompt,     'legion/cli/prompt_command'
    autoload :Image,      'legion/cli/image_command'
    autoload :Dataset,    'legion/cli/dataset_command'
    autoload :Cost,        'legion/cli/cost_command'
    autoload :Team,        'legion/cli/team_command'
    autoload :Marketplace, 'legion/cli/marketplace_command'
    autoload :Notebook,    'legion/cli/notebook_command'
    autoload :Llm,         'legion/cli/llm_command'
    autoload :Tty,            'legion/cli/tty_command'
    autoload :ObserveCommand, 'legion/cli/observe_command'
    autoload :Payroll,        'legion/cli/payroll_command'
    autoload :DoCommand,   'legion/cli/do_command'
    autoload :Interactive, 'legion/cli/interactive'
    autoload :Docs,        'legion/cli/docs_command'
    autoload :Failover,    'legion/cli/failover_command'
    autoload :AbsorbCommand,   'legion/cli/absorb_command'
    autoload :ConnectCommand,  'legion/cli/connect_command'
    autoload :Apollo,          'legion/cli/apollo_command'
    autoload :TraceCommand, 'legion/cli/trace_command'
    autoload :Features,     'legion/cli/features_command'
    autoload :Debug,        'legion/cli/debug_command'
    autoload :CodegenCommand, 'legion/cli/codegen_command'
    autoload :Bootstrap,      'legion/cli/bootstrap_command'
    autoload :Broker,         'legion/cli/broker_command'
    autoload :AdminCommand,   'legion/cli/admin_command'

    module Groups
      autoload :Ai,       'legion/cli/groups/ai_group'
      autoload :Git,      'legion/cli/groups/git_group'
      autoload :Pipeline, 'legion/cli/groups/pipeline_group'
      autoload :Ops,      'legion/cli/groups/ops_group'
      autoload :Serve,    'legion/cli/groups/serve_group'
      autoload :Admin,    'legion/cli/groups/admin_group'
      autoload :Dev,      'legion/cli/groups/dev_group'
    end

    class Main < Thor
      def self.exit_on_failure?
        true
      end

      def self.start(given_args = ARGV, config = {})
        super
      rescue Legion::CLI::Error => e
        Legion::Logging.error("CLI::Main.start CLI error: #{e.message}") if defined?(Legion::Logging)
        formatter = Output::Formatter.new(json: given_args.include?('--json'), color: !given_args.include?('--no-color'))
        ErrorHandler.format_error(e, formatter)
        ErrorForwarder.forward_error(e, command: given_args.join(' '))
        exit(1)
      rescue StandardError => e
        Legion::Logging.error("CLI::Main.start unexpected error: #{e.message}") if defined?(Legion::Logging)
        wrapped = ErrorHandler.wrap(e)
        formatter = Output::Formatter.new(json: given_args.include?('--json'), color: !given_args.include?('--no-color'))
        ErrorHandler.format_error(wrapped, formatter)
        ErrorForwarder.forward_error(e, command: given_args.join(' '))
        exit(1)
      end

      LEGION_GEMS = %w[
        legion-transport legion-cache legion-crypt legion-data
        legion-json legion-logging legion-settings
        legion-llm legion-gaia legion-mcp legion-rbac
        legion-tty legion-ffi
      ].freeze

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'version', 'Show version information'
      map %w[-v --version] => :version
      option :full, type: :boolean, default: false, desc: 'Include all installed lex-* extension versions'
      def version
        out = formatter
        lexs = discovered_lexs
        if options[:json]
          payload = { version: Legion::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
                      components: installed_components, extensions: lexs.size }
          payload[:extension_versions] = lex_versions(lexs) if options[:full]
          out.json(payload)
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
          puts "  #{out.colorize("#{lexs.size} extension(s)", :accent)} installed"

          if options[:full] && lexs.any?
            out.spacer
            out.header('Extensions')
            lex_versions(lexs).each do |name, ver|
              puts "  #{out.colorize(name.ljust(20), :label)} #{ver}"
            end
          end
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
      option :http_port, type: :numeric, desc: 'HTTP API port (overrides settings)'
      option :lite, type: :boolean, default: false, desc: 'Start in lite mode (no external services)'
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
      option :privacy, type: :boolean, default: false, desc: 'Verify enterprise privacy mode'
      def check
        exit_code = if options[:privacy]
                      Legion::CLI::Check.run_privacy(formatter, options)
                    else
                      Legion::CLI::Check.run(formatter, options)
                    end
        exit(exit_code) if exit_code != 0
      end

      # --- Core framework ---
      desc 'lex SUBCOMMAND', 'Manage Legion extensions (LEXs)'
      subcommand 'lex', Legion::CLI::Lex

      desc 'task SUBCOMMAND', 'Manage tasks'
      subcommand 'task', Legion::CLI::Task

      desc 'chain SUBCOMMAND', 'Manage task chains'
      subcommand 'chain', Legion::CLI::Chain

      desc 'config SUBCOMMAND', 'View and validate configuration'
      subcommand 'config', Legion::CLI::Config

      desc 'schedule SUBCOMMAND', 'Manage schedules'
      subcommand 'schedule', Legion::CLI::Schedule

      desc 'coldstart SUBCOMMAND', 'Cold start bootstrap and Claude memory ingestion'
      subcommand 'coldstart', Legion::CLI::Coldstart

      # --- Health & maintenance ---
      desc 'doctor', 'Diagnose environment and suggest fixes'
      subcommand 'doctor', Legion::CLI::Doctor

      desc 'setup SUBCOMMAND', 'Install feature packs and configure IDE integrations'
      subcommand 'setup', Legion::CLI::Setup

      desc 'bootstrap SOURCE', 'One-command setup: fetch config, scaffold, and install packs'
      subcommand 'bootstrap', Legion::CLI::Bootstrap

      desc 'update', 'Update Legion gems to latest versions'
      subcommand 'update', Legion::CLI::Update

      desc 'init', 'Initialize a new Legion workspace'
      subcommand 'init', Legion::CLI::Init

      # --- Interactive & shortcuts ---
      desc 'codegen SUBCOMMAND', 'Manage self-generating functions'
      subcommand 'codegen', CodegenCommand

      desc 'tty', 'Rich terminal UI (onboarding, AI chat, dashboard)'
      subcommand 'tty', Legion::CLI::Tty

      # --- Command groups ---
      desc 'ai SUBCOMMAND', 'AI, cognitive, and knowledge commands'
      subcommand 'ai', Legion::CLI::Groups::Ai

      desc 'git SUBCOMMAND', 'AI-assisted git workflow (commit, pr, review)'
      subcommand 'git', Legion::CLI::Groups::Git

      desc 'pipeline SUBCOMMAND', 'LLM pipeline tools (prompts, evals, datasets, skills)'
      subcommand 'pipeline', Legion::CLI::Groups::Pipeline

      desc 'ops SUBCOMMAND', 'Observability, cost, audit, and operations'
      subcommand 'ops', Legion::CLI::Groups::Ops

      desc 'serve SUBCOMMAND', 'Protocol servers (MCP, ACP)'
      subcommand 'serve', Legion::CLI::Groups::Serve

      desc 'admin SUBCOMMAND', 'Auth, RBAC, workers, and teams'
      subcommand 'admin', Legion::CLI::Groups::Admin

      desc 'dev SUBCOMMAND', 'Generators, docs, marketplace, and shell completion'
      subcommand 'dev', Legion::CLI::Groups::Dev

      desc 'absorb SUBCOMMAND', 'Absorb content from external sources'
      subcommand 'absorb', AbsorbCommand

      desc 'auth SUBCOMMAND', 'Authenticate with external services (Teams, Kerberos)'
      subcommand 'auth', Auth

      desc 'connect PROVIDER', 'Connect external accounts via OAuth2'
      subcommand 'connect', ConnectCommand

      desc 'broker SUBCOMMAND', 'RabbitMQ broker management (stats, cleanup)'
      subcommand 'broker', Legion::CLI::Broker

      desc 'tree', 'Print a tree of all available commands'
      def tree
        legion_print_command_tree(self.class, ::File.basename($PROGRAM_NAME), '')
      end

      desc 'ask TEXT', 'Quick AI prompt (shortcut for chat prompt)'
      map %w[-p --prompt] => :ask
      def ask(*text)
        Legion::CLI::Chat.start(['prompt', text.join(' ')] + ARGV.select { |a| a.start_with?('--') })
      end

      desc 'do TEXT', 'Route a natural language intent to the right extension'
      long_desc <<~DESC
        Describe what you want in plain English. Legion routes to the best
        matching extension and runner automatically.

        Examples:
          legion do "check consul health"
          legion do "list running tasks"
          legion do "review the latest PR"
      DESC
      def do_action(*text)
        Legion::CLI::DoCommand.run(text.join(' '), formatter, options)
      end
      map 'do' => :do_action

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
      rescue Net::ReadTimeout => e
        Legion::Logging.debug("CLI#dream read timeout (expected for background tasks): #{e.message}") if defined?(Legion::Logging)
        out.success('Dream cycle triggered on daemon (running in background)')
      rescue Errno::ECONNREFUSED => e
        Legion::Logging.warn("CLI#dream daemon not running: #{e.message}") if defined?(Legion::Logging)
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
          LEGION_GEMS.each do |gem_name|
            short = gem_name.sub('legion-', '')
            spec = Gem::Specification.find_by_name(gem_name)
            components[short.to_sym] = spec.version.to_s
          rescue Gem::MissingSpecError => e
            Legion::Logging.debug("CLI#installed_components gem #{gem_name} not installed: #{e.message}") if defined?(Legion::Logging)
            components[short.to_sym] = '(not installed)'
          end
          components
        end

        def discovered_lexs
          Gem::Specification.select { |s| s.name.start_with?('lex-') }
                            .group_by(&:name)
                            .transform_values { |specs| specs.max_by(&:version) }
        end

        def lex_versions(lexs)
          lexs.sort_by { |name, _| name }.to_h { |name, spec| [name, spec.version.to_s] }
        end

        def find_pidfile
          %w[/var/run/legion.pid /tmp/legion.pid].find { |f| File.exist?(f) }
        end

        def api_port
          require 'legion/settings'
          Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
          api_settings = Legion::Settings[:api]
          (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
        rescue StandardError => e
          Legion::Logging.debug("CLI#api_port failed: #{e.message}") if defined?(Legion::Logging)
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
