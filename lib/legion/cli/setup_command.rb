# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'thor'
require 'rbconfig'
require 'legion/cli/output'

module Legion
  module CLI
    class Setup < Thor
      namespace 'setup'

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :force,    type: :boolean, default: false, desc: 'Overwrite existing config'

      LEGION_MCP_ENTRY = {
        'command' => 'legionio',
        'args'    => %w[mcp stdio]
      }.freeze

      PACKS = {
        agentic:  {
          description: 'Full cognitive stack: core libs, agentic domains, AI providers, and operational extensions',
          gems:        %w[
            legion-apollo legion-gaia legion-llm legion-mcp legion-rbac
            lex-acp lex-adapter lex-agentic-affect lex-agentic-attention
            lex-agentic-defense lex-agentic-executive lex-agentic-homeostasis
            lex-agentic-imagination lex-agentic-inference lex-agentic-integration
            lex-agentic-language lex-agentic-learning lex-agentic-memory
            lex-agentic-self lex-agentic-social lex-apollo lex-audit lex-autofix
            lex-azure-ai lex-bedrock lex-claude lex-codegen lex-coldstart
            lex-conditioner lex-cortex lex-cost-scanner lex-dataset lex-detect
            lex-eval lex-exec lex-extinction lex-factory lex-finops lex-foundry
            lex-gemini lex-governance lex-kerberos lex-knowledge lex-llm-gateway
            lex-metering lex-mesh lex-microsoft_teams lex-mind-growth lex-node
            lex-onboard lex-openai lex-pilot-infra-monitor
            lex-pilot-knowledge-assist lex-privatecore lex-prompt lex-react
            lex-swarm lex-swarm-github lex-synapse lex-telemetry lex-tick
            lex-transformer lex-xai
          ]
        },
        llm:      {
          description: 'LLM routing and provider integration (no cognitive stack)',
          gems:        %w[legion-llm]
        },
        channels: {
          description: 'Channel adapters for chat platforms',
          gems:        %w[lex-slack lex-microsoft_teams]
        }
      }.freeze

      SKILL_CONTENT = <<~MARKDOWN
        ---
        name: legion
        description: Orchestrate LegionIO extensions and agents
        ---

        You have access to LegionIO MCP tools. When the user asks you to work with Legion:

        1. Use `legion.discover_tools` to find relevant capabilities
        2. Use `legion.do_action` for natural language task routing
        3. Use `legion.run_task` to execute specific extension functions
        4. Use `legion.list_peers` and `legion.ask_peer` for agent coordination
        5. Present results as a consolidated summary
      MARKDOWN

      desc 'claude-code', 'Install Legion MCP server and slash command skill for Claude Code'
      def claude_code
        out = formatter
        installed = []

        install_claude_mcp(installed)
        install_claude_skill(installed)
        install_claude_hooks(installed)

        if options[:json]
          out.json(platform: 'claude-code', installed: installed)
        else
          out.spacer
          out.success("Legion configured for Claude Code (#{installed.size} item(s))")
          out.spacer
          puts "  Run '/legion' in Claude Code to use your LegionIO tools."
        end
      end

      desc 'cursor', 'Install Legion MCP server config for Cursor'
      def cursor
        out = formatter
        path = File.join(Dir.pwd, '.cursor', 'mcp.json')
        installed = []

        write_mcp_servers_json(nil, path, installed)

        if options[:json]
          out.json(platform: 'cursor', installed: installed)
        else
          out.spacer
          out.success("Legion configured for Cursor (#{installed.size} item(s))")
          out.spacer
          puts "  MCP config written to: #{path}"
        end
      end

      desc 'vscode', 'Install Legion MCP server config for VS Code'
      def vscode
        out = formatter
        path = File.join(Dir.pwd, '.vscode', 'mcp.json')
        installed = []

        write_vscode_mcp_json(nil, path, installed)

        if options[:json]
          out.json(platform: 'vscode', installed: installed)
        else
          out.spacer
          out.success("Legion configured for VS Code (#{installed.size} item(s))")
          out.spacer
          puts "  MCP config written to: #{path}"
        end
      end

      desc 'agentic', 'Install full cognitive stack (GAIA + LLM + Apollo + all agentic extensions)'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      def agentic
        install_pack(:agentic)
      end
      map 'give-me-all-the-brains' => :agentic
      map 'brains' => :agentic

      desc 'llm', 'Install LLM routing and provider integration'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      def llm
        install_pack(:llm)
      end

      desc 'channels', 'Install channel adapters (Slack, Teams)'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      def channels
        install_pack(:channels)
      end

      desc 'packs', 'Show installed feature packs and available gems'
      def packs
        out = formatter
        pack_statuses = PACKS.map do |name, pack|
          installed, missing = partition_gems(pack[:gems])
          { name: name, description: pack[:description],
            installed: installed.map { |g| { name: g, version: gem_version(g) } },
            missing: missing }
        end

        if options[:json]
          out.json(packs: pack_statuses)
        else
          out.header('Feature Packs')
          out.spacer
          pack_statuses.each do |ps|
            all_installed = ps[:missing].empty?
            icon = all_installed ? out.colorize('installed', :success) : out.colorize('not installed', :muted)
            puts "  #{out.colorize(ps[:name].to_s.ljust(12), :label)} #{icon}  #{ps[:description]}"
            ps[:installed].each do |g|
              puts "    #{out.colorize(g[:name], :success)} #{g[:version]}"
            end
            ps[:missing].each do |g|
              puts "    #{out.colorize(g, :muted)} (missing)"
            end
          end
          out.spacer
        end
      end

      desc 'status', 'Show which platforms have Legion MCP configured'
      def status
        out = formatter
        platforms = check_all_platforms

        if options[:json]
          out.json(platforms: platforms)
        else
          out.header('Legion MCP Setup Status')
          out.spacer
          platforms.each do |p|
            icon = p[:configured] ? out.colorize('configured', :success) : out.colorize('not configured', :muted)
            puts "  #{out.colorize(p[:name].ljust(16), :label)} #{icon}"
            puts "    #{out.colorize(p[:path], :muted)}" if p[:path]
          end
          out.spacer
          configured_count = platforms.count { |p| p[:configured] }
          puts "  #{configured_count} of #{platforms.size} platform(s) configured"
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def install_pack(pack_name)
          pack = PACKS[pack_name]
          installed, missing = partition_gems(pack[:gems])

          return report_already_installed(pack_name, installed) if missing.empty?
          return report_dry_run(pack_name, installed, missing) if options[:dry_run]

          execute_pack_install(pack_name, installed, missing)
        end

        def report_already_installed(pack_name, installed)
          out = formatter
          if options[:json]
            out.json(pack: pack_name, status: 'already_installed',
                     gems: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.success("#{pack_name} pack already installed")
            installed.each { |g| puts "  #{g} #{gem_version(g)}" }
          end
        end

        def report_dry_run(pack_name, installed, missing)
          out = formatter
          if options[:json]
            out.json(pack: pack_name, status: 'dry_run', to_install: missing,
                     already_installed: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.header("#{pack_name} pack (dry run)")
            missing.each { |g| puts "  #{out.colorize('install', :accent)} #{g}" }
            installed.each { |g| puts "  #{out.colorize('skip', :muted)} #{g} #{gem_version(g)} (already installed)" }
          end
        end

        def execute_pack_install(pack_name, installed, missing)
          out = formatter
          out.header("Installing #{pack_name} pack") unless options[:json]
          gem_bin = File.join(RbConfig::CONFIG['bindir'], 'gem')
          results = missing.map { |g| install_gem(g, gem_bin, out) }

          Gem::Specification.reset
          successes, failures = results.partition { |r| r[:status] == 'installed' }

          if options[:json]
            out.json(pack: pack_name, installed: successes, failed: failures,
                     already_present: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.spacer
            if failures.empty?
              out.success("#{pack_name} pack installed (#{successes.size} gem(s))")
              suggest_next_steps(out, pack_name)
            else
              out.error("#{failures.size} gem(s) failed to install")
              failures.each { |f| puts "  #{f[:name]}: #{f[:error]}" }
            end
          end
        end

        def partition_gems(gem_names)
          installed = []
          missing = []
          gem_names.each do |name|
            Gem::Specification.find_by_name(name)
            installed << name
          rescue Gem::MissingSpecError
            missing << name
          end
          [installed, missing]
        end

        def gem_version(name)
          Gem::Specification.find_by_name(name).version.to_s
        rescue Gem::MissingSpecError
          nil
        end

        def install_gem(name, gem_bin, out)
          puts "  Installing #{name}..." unless options[:json]
          output = `#{gem_bin} install #{name} --no-document 2>&1`
          if $CHILD_STATUS.success?
            out.success("  #{name} installed") unless options[:json]
            { name: name, status: 'installed' }
          else
            out.error("  #{name} failed") unless options[:json]
            { name: name, status: 'failed', error: output.strip.lines.last&.strip }
          end
        end

        def suggest_next_steps(out, pack_name)
          out.spacer
          case pack_name
          when :agentic
            puts '  Next steps:'
            puts '    legion start          # full daemon with cognitive stack'
            puts '    legion start --lite   # single-process, no external services'
            puts '    legion chat           # interactive AI conversation'
          when :llm
            puts '  Next steps:'
            puts '    legion chat           # interactive AI conversation'
            puts '    legion llm status     # check provider connectivity'
          when :channels
            puts '  Next steps:'
            puts '    Configure channels in settings: {"gaia": {"channels": {"slack": {"enabled": true}}}}'
          end
        end

        def install_claude_mcp(installed)
          settings_path = File.expand_path('~/.claude/settings.json')
          existing = load_json_file(settings_path)
          servers  = existing['mcpServers'] || {}

          if servers.key?('legion') && !options[:force]
            puts '  Claude Code MCP entry already present (use --force to overwrite)' unless options[:json]
            return
          end

          servers['legion'] = LEGION_MCP_ENTRY
          existing['mcpServers'] = servers

          write_json_file(settings_path, existing)
          installed << settings_path
          puts "  Wrote MCP server entry to #{settings_path}" unless options[:json]
        end

        def install_claude_skill(installed)
          skill_path = File.expand_path('~/.claude/commands/legion.md')

          if File.exist?(skill_path) && !options[:force]
            puts '  Claude Code skill already present (use --force to overwrite)' unless options[:json]
            return
          end

          FileUtils.mkdir_p(File.dirname(skill_path))
          File.write(skill_path, SKILL_CONTENT)
          installed << skill_path
          puts "  Wrote slash command skill to #{skill_path}" unless options[:json]
        end

        def install_claude_hooks(installed)
          settings_path = File.expand_path('~/.claude/settings.json')
          existing = load_json_file(settings_path)

          hooks = existing['hooks'] || {}

          has_commit  = Array(hooks['PostToolUse']).any? { |h| h['command']&.include?('knowledge capture commit') }
          has_session = Array(hooks['Stop']).any? { |h| h['command']&.include?('knowledge capture session') }
          if has_commit && has_session && !options[:force]
            puts '  Write-back hooks already present (use --force to overwrite)' unless options[:json]
            return
          end

          hooks['PostToolUse'] ||= []
          hooks['Stop'] ||= []

          unless has_commit
            hooks['PostToolUse'] << {
              'matcher' => 'Bash',
              'command' => 'legionio knowledge capture commit',
              'timeout' => 10_000
            }
          end

          unless has_session
            hooks['Stop'] << {
              'command' => 'legionio knowledge capture session',
              'timeout' => 15_000
            }
          end

          existing['hooks'] = hooks
          write_json_file(settings_path, existing)
          installed << 'hooks'
          puts '  Installed write-back hooks for knowledge capture' unless options[:json]
        end

        def write_mcp_servers_json(_out, path, installed)
          existing = load_json_file(path)
          servers  = existing['mcpServers'] || {}

          if servers.key?('legion') && !options[:force]
            puts "  Legion entry already present in #{path} (use --force to overwrite)" unless options[:json]
            return
          end

          servers['legion'] = LEGION_MCP_ENTRY
          existing['mcpServers'] = servers

          write_json_file(path, existing)
          installed << path
          puts "  Wrote MCP config to #{path}" unless options[:json]
        end

        def write_vscode_mcp_json(_out, path, installed)
          existing = load_json_file(path)
          servers  = existing['servers'] || {}

          if servers.key?('legion') && !options[:force]
            puts "  Legion entry already present in #{path} (use --force to overwrite)" unless options[:json]
            return
          end

          servers['legion'] = {
            'type'    => 'stdio',
            'command' => 'legionio',
            'args'    => %w[mcp stdio]
          }
          existing['servers'] = servers

          write_json_file(path, existing)
          installed << path
          puts "  Wrote MCP config to #{path}" unless options[:json]
        end

        def load_json_file(path)
          return {} unless File.exist?(path)

          ::JSON.parse(File.read(path))
        rescue ::JSON::ParserError => e
          Legion::Logging.warn("SetupCommand#load_json_file invalid JSON in #{path}: #{e.message}") if defined?(Legion::Logging)
          {}
        end

        def write_json_file(path, data)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, ::JSON.pretty_generate(data))
        end

        def check_all_platforms
          [
            check_claude_code,
            check_cursor,
            check_vscode
          ]
        end

        def check_claude_code
          path = File.expand_path('~/.claude/settings.json')
          configured = begin
            data = ::JSON.parse(File.read(path))
            data.dig('mcpServers', 'legion') ? true : false
          rescue StandardError => e
            Legion::Logging.debug("SetupCommand#check_claude_code failed: #{e.message}") if defined?(Legion::Logging)
            false
          end
          { name: 'Claude Code', path: path, configured: configured }
        end

        def check_cursor
          path = File.join(Dir.pwd, '.cursor', 'mcp.json')
          configured = begin
            data = ::JSON.parse(File.read(path))
            data.dig('mcpServers', 'legion') ? true : false
          rescue StandardError => e
            Legion::Logging.debug("SetupCommand#check_cursor failed: #{e.message}") if defined?(Legion::Logging)
            false
          end
          { name: 'Cursor', path: path, configured: configured }
        end

        def check_vscode
          path = File.join(Dir.pwd, '.vscode', 'mcp.json')
          configured = begin
            data = ::JSON.parse(File.read(path))
            data.dig('servers', 'legion') ? true : false
          rescue StandardError => e
            Legion::Logging.debug("SetupCommand#check_vscode failed: #{e.message}") if defined?(Legion::Logging)
            false
          end
          { name: 'VS Code', path: path, configured: configured }
        end
      end
    end
  end
end
