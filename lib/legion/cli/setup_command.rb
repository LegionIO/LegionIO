# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'thor'
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
