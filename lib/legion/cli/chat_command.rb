# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Chat < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Model ID (e.g., claude-sonnet-4-6)'
      class_option :provider,   type: :string,  desc: 'LLM provider (bedrock, anthropic, openai, gemini, ollama)'
      class_option :system,       type: :string,  desc: 'System prompt override'
      class_option :auto_approve, type: :boolean, default: false, aliases: ['-y'],
                                  desc: 'Auto-approve all tool executions (skip confirmation prompts)'
      class_option :no_markdown,  type: :boolean, default: false,
                                  desc: 'Disable markdown rendering (raw output)'
      class_option :max_budget_usd, type: :numeric, desc: 'Maximum estimated cost in USD (stops when exceeded)'
      class_option :incognito, type: :boolean, default: false,
                               desc: 'Disable automatic session history saving'
      class_option :continue, type: :boolean, default: false, aliases: ['-c'],
                              desc: 'Resume the most recent session'
      class_option :resume,   type: :string, desc: 'Resume a saved session by name'
      class_option :fork,     type: :string, desc: 'Fork a saved session (load but save as new)'

      autoload :Session, 'legion/cli/chat/session'

      desc 'interactive', 'Start interactive AI conversation'
      def interactive
        out = formatter
        setup_chat_logger
        setup_connection

        chat_obj = create_chat
        configure_permissions(:interactive)
        system_prompt = build_system_prompt
        @session = Chat::Session.new(
          chat: chat_obj, system_prompt: system_prompt,
          budget_usd: options[:max_budget_usd]
        )

        restore_session(out) if options[:continue] || options[:resume] || options[:fork]
        load_memory_context
        load_custom_agents

        chat_log.info "session started model=#{@session.model_id} incognito=#{options[:incognito]}"
        out.banner(version: Legion::VERSION)
        puts
        puts out.dim("  Model: #{@session.model_id}")
        puts out.dim('  Type /help for commands, /quit to exit')
        puts

        repl_loop(out)
      rescue Interrupt
        puts
        puts out.dim('Interrupted.')
        show_session_stats(out) if @session
      rescue CLI::Error => e
        chat_log.error "cli_error: #{e.message}"
        out.error(e.message)
        raise SystemExit, 1
      ensure
        auto_save_session(out) if @session
        chat_log&.info('session ended')
        Connection.shutdown
      end
      default_task :interactive

      desc 'prompt TEXT', 'Send a single prompt and exit (headless mode)'
      option :output_format, type: :string, default: 'text', desc: 'Output format: text, json'
      option :max_turns, type: :numeric, default: 10, desc: 'Maximum tool-use turns'
      def prompt(text)
        out = formatter
        setup_chat_logger
        setup_connection

        text = combine_with_stdin(text)
        raise CLI::Error, 'No prompt text provided. Pass text as argument or pipe via stdin.' if text.empty?

        chat_obj = create_chat
        configure_permissions(:headless)
        system_prompt = build_system_prompt
        session = Chat::Session.new(
          chat: chat_obj, system_prompt: system_prompt,
          budget_usd: options[:max_budget_usd]
        )

        chat_log.info "headless prompt model=#{session.model_id} length=#{text.length}"

        response = if options[:output_format] == 'json'
                     session.send_message(text)
                   else
                     session.send_message(text) { |chunk| print chunk.content if chunk.content }
                   end

        chat_log.info "headless complete tokens_in=#{session.stats[:input_tokens]} tokens_out=#{session.stats[:output_tokens]}"

        if options[:output_format] == 'json'
          out.json({
                     response: response.content,
                     model:    session.model_id,
                     stats:    session.stats
                   })
        else
          puts unless response.content&.end_with?("\n")
        end
      rescue CLI::Error => e
        chat_log&.error("cli_error: #{e.message}")
        out.error(e.message)
        raise SystemExit, 1
      rescue StandardError => e
        chat_log&.error("prompt_error: #{e.message}")
        warn "Error: #{e.message}"
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_chat_logger
          require 'legion/cli/chat/chat_logger'
          ChatLogger.setup(level: options[:verbose] ? 'debug' : 'info')
        end

        def chat_log
          ChatLogger.logger
        end

        def setup_connection
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_llm
        end

        def render_response(text, out)
          return text if options[:no_markdown] || options[:no_color]

          require 'legion/cli/chat/markdown_renderer'
          Chat::MarkdownRenderer.render(text, color: out.color_enabled)
        rescue LoadError
          text
        end

        def combine_with_stdin(text)
          return text if $stdin.tty?

          piped = $stdin.read
          return piped.strip if text.strip.empty?

          "#{text}\n\n#{piped}"
        end

        def configure_permissions(default)
          require 'legion/cli/chat/permissions'
          Chat::Permissions.mode = if options[:auto_approve]
                                     :auto_approve
                                   else
                                     default
                                   end
        end

        def create_chat
          opts = {}
          opts[:model]    = options[:model] if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]

          require 'legion/cli/chat/tool_registry'
          chat = Legion::LLM.chat(**opts)
          chat.with_tools(*Chat::ToolRegistry.builtin_tools)
          chat
        end

        def build_system_prompt
          return options[:system] if options[:system]

          require 'legion/cli/chat/context'
          Chat::Context.to_system_prompt(Dir.pwd)
        end

        def repl_loop(out)
          require 'reline'

          loop do
            line = Reline.readline(prompt_string, true)
            break if line.nil? # Ctrl+D

            stripped = line.strip
            next if stripped.empty?

            if stripped.start_with?('/')
              handled = handle_slash_command(stripped, out)
              next if handled
            end

            if stripped.start_with?('@')
              handled = handle_at_mention(stripped, out)
              next if handled
            end

            chat_log.debug "user_message length=#{stripped.length}"
            print out.colorize('legion', :title)
            print out.dim(' > ')

            buffer = String.new
            @session.send_message(
              stripped,
              on_tool_call:   lambda { |tc|
                chat_log.debug "tool_call name=#{tc.name} args=#{tc.arguments.keys.join(',')}"
                puts out.dim("  [tool] #{tc.name}(#{tc.arguments.keys.join(', ')})")
              },
              on_tool_result: lambda { |tr|
                result_preview = tr.to_s.lines.first(3).join.rstrip
                chat_log.debug "tool_result preview=#{result_preview[0..200]}"
                puts out.dim("  [result] #{result_preview}")
              }
            ) do |chunk|
              buffer << chunk.content if chunk.content
            end
            chat_log.debug "response length=#{buffer.length} tokens_in=#{@session.stats[:input_tokens]} tokens_out=#{@session.stats[:output_tokens]}"
            print render_response(buffer, out)
            puts
            puts
          rescue Chat::Session::BudgetExceeded => e
            chat_log.warn "budget_exceeded: #{e.message}"
            puts
            out.error(e.message)
            break
          rescue Interrupt
            puts
            next
          rescue StandardError => e
            chat_log.error "llm_error: #{e.class}: #{e.message}"
            puts
            out.error("LLM error: #{e.message}")
            puts
          end

          puts
          puts out.dim('Goodbye.')
          show_session_stats(out)
        end

        def prompt_string
          "\001\e[38;2;127;119;221m\002you\001\e[0m\002 > "
        end

        def handle_slash_command(input, out)
          cmd, *args = input.split(' ', 2)
          chat_log.debug "slash_command: #{cmd}"
          case cmd.downcase
          when '/quit', '/exit', '/q'
            show_session_stats(out)
            auto_save_session(out)
            raise SystemExit, 0
          when '/help', '/h'
            show_help(out)
          when '/cost'
            show_session_stats(out)
          when '/clear'
            @session.chat.reset_messages!
            chat_log.info 'conversation cleared'
            out.success('Conversation cleared')
          when '/save'
            handle_save(args.first, out)
          when '/load'
            handle_load(args.first, out)
          when '/sessions'
            handle_sessions(out)
          when '/compact'
            handle_compact(out)
          when '/fetch'
            handle_fetch(args.first, out)
          when '/rewind'
            handle_rewind(args.first, out)
          when '/memory'
            handle_memory(args.first, out)
          when '/search'
            handle_search(args.first, out)
          when '/agent'
            handle_agent(args.first, out)
          when '/agents'
            handle_agents_status(out)
          when '/plan'
            handle_plan_toggle(out)
          when '/swarm'
            handle_swarm(args.first, out)
          when '/model'
            if args.first
              @session.chat.with_model(args.first)
              chat_log.info "model_switch to=#{args.first}"
              out.success("Switched to model: #{args.first}")
            else
              puts "  Current model: #{@session.model_id}"
            end
          else
            out.warn("Unknown command: #{cmd}. Type /help for available commands.")
          end
          true
        end

        def handle_save(name, out)
          require 'legion/cli/chat/session_store'
          name ||= Time.now.strftime('%Y%m%d-%H%M%S')
          @session_name = name
          path = Chat::SessionStore.save(@session, name)
          out.success("Session saved: #{name} (#{path})")
        rescue StandardError => e
          out.error("Save failed: #{e.message}")
        end

        def handle_load(name, out)
          require 'legion/cli/chat/session_store'
          unless name
            out.error('Usage: /load <name>. Use /sessions to list saved sessions.')
            return
          end
          data = Chat::SessionStore.load(name)
          Chat::SessionStore.restore(@session, data)
          msg_count = data[:messages]&.length || 0
          out.success("Loaded session: #{name} (#{msg_count} messages)")
        rescue CLI::Error => e
          out.error(e.message)
        end

        def handle_sessions(_out)
          require 'legion/cli/chat/session_store'
          sessions = Chat::SessionStore.list
          if sessions.empty?
            puts '  No saved sessions.'
            return
          end
          sessions.each do |s|
            age = Time.now - s[:modified]
            ago = age < 3600 ? "#{(age / 60).round}m ago" : "#{(age / 3600).round}h ago"
            puts "  #{s[:name]}  (#{ago})"
          end
        end

        def show_help(out)
          out.header('Chat Commands')
          out.detail({
                       '/help'              => 'Show this help',
                       '/quit'              => 'Exit chat',
                       '/cost'              => 'Show session stats',
                       '/compact'           => 'Compress conversation history',
                       '/clear'             => 'Clear conversation history',
                       '/save NAME'         => 'Save session to disk',
                       '/load NAME'         => 'Load a saved session',
                       '/fetch URL'         => 'Fetch a web page into context',
                       '/search QUERY'      => 'Web search and inject results into context',
                       '/rewind [N|FILE]'   => 'Undo file edits (last, N steps, or specific file)',
                       '/memory [add TEXT]' => 'View or add persistent memory',
                       '/agent TASK'        => 'Spawn a background subagent',
                       '/agents'            => 'Show running subagents',
                       '/plan'              => 'Toggle plan mode (read-only)',
                       '/swarm NAME|PROMPT' => 'Run a swarm workflow or auto-generate one',
                       '/sessions'          => 'List saved sessions',
                       '/model X'           => 'Switch model'
                     })
          puts
          puts out.dim('  Sessions auto-saved on exit. Use --incognito to disable.')
        end

        def handle_compact(out)
          messages = @session.chat.messages
          if messages.length < 4
            out.warn('Not enough conversation history to compact.')
            return
          end

          before_count = messages.length
          summary = @session.send_message(
            'Summarize our entire conversation so far in a concise paragraph. ' \
            'Include key decisions, code changes, and any important context. ' \
            'This summary will replace the full history to save tokens.'
          )

          @session.chat.reset_messages!
          @session.chat.add_message(role: :assistant, content: summary.content)

          out.success("Compacted #{before_count} messages into 1 summary message")
        rescue StandardError => e
          out.error("Compact failed: #{e.message}")
        end

        def handle_fetch(url, out)
          unless url && !url.strip.empty?
            out.error('Usage: /fetch <url>')
            return
          end

          require 'legion/cli/chat/web_fetch'
          out.header("Fetching #{url}...")
          content = Chat::WebFetch.fetch(url.strip)
          chat_log.info "web_fetch url=#{url} length=#{content.length}"

          @session.chat.add_message(role: :user, content: "Content from #{url}:\n\n#{content}")
          out.success("Fetched #{content.length} chars into context. Ask questions about it.")
        rescue Chat::WebFetch::FetchError => e
          chat_log.warn "web_fetch_error url=#{url} error=#{e.message}"
          out.error("Fetch failed: #{e.message}")
        end

        def handle_memory(arg, out)
          require 'legion/cli/chat/memory_store'
          if arg&.start_with?('add ')
            text = arg.sub('add ', '').strip
            if text.empty?
              out.error('Usage: /memory add <text>')
              return
            end
            path = Chat::MemoryStore.add(text)
            chat_log.info "memory_add length=#{text.length}"
            out.success("Saved to project memory (#{path})")
          else
            entries = Chat::MemoryStore.list
            global_entries = Chat::MemoryStore.list(scope: :global)
            if entries.empty? && global_entries.empty?
              out.warn('No memory entries. Use /memory add <text> to save something.')
              return
            end
            unless global_entries.empty?
              puts out.dim('  Global:')
              global_entries.each { |e| puts "    - #{e}" }
            end
            unless entries.empty?
              puts out.dim('  Project:')
              entries.each { |e| puts "    - #{e}" }
            end
          end
        end

        def handle_search(query, out)
          unless query && !query.strip.empty?
            out.error('Usage: /search <query>')
            return
          end

          require 'legion/cli/chat/web_search'
          out.header("Searching: #{query}...")
          results = Chat::WebSearch.search(query.strip)
          chat_log.info "web_search query=#{query} results=#{results[:results].length}"

          summary = results[:results].map { |r| "- [#{r[:title]}](#{r[:url]})\n  #{r[:snippet]}" }.join("\n\n")
          context = "Web search results for '#{query}':\n\n#{summary}"

          context += "\n\n---\n\nTop result content:\n\n#{results[:fetched_content]}" if results[:fetched_content]

          @session.chat.add_message(role: :user, content: context)
          out.success("#{results[:results].length} results injected into context.")
        rescue Chat::WebSearch::SearchError => e
          chat_log.warn "web_search_error query=#{query} error=#{e.message}"
          out.error("Search failed: #{e.message}")
        end

        def handle_swarm(arg, out)
          unless arg && !arg.strip.empty?
            out.error('Usage: /swarm <workflow-name> or /swarm <task description>')
            return
          end

          workflow_path = File.join(Dir.pwd, '.legion/swarms', "#{arg.strip}.json")
          if File.exist?(workflow_path)
            chat_log.info "swarm_start workflow=#{arg.strip}"
            out.header("Starting swarm: #{arg.strip}")
            Thread.new do
              Legion::CLI::Swarm.new.invoke(:start, [arg.strip])
            rescue StandardError => e
              puts out.dim("\n  [swarm] Error: #{e.message}")
            end
            out.success('Swarm running in background. Results will appear when done.')
          else
            chat_log.info "swarm_generate prompt_length=#{arg.length}"
            out.warn("No workflow file found for '#{arg.strip}'. Auto-generation from prompt is planned but not yet implemented.")
            out.dim("  Create a workflow file at: #{workflow_path}")
          end
        end

        def handle_plan_toggle(out)
          @plan_mode = !@plan_mode
          if @plan_mode
            # Remove write/edit/shell tools, keep read/search only
            read_only_tools = @session.chat.instance_variable_get(:@tools)&.select do |t|
              t.is_a?(Class) && [Chat::Tools::ReadFile, Chat::Tools::SearchFiles,
                                 Chat::Tools::SearchContent, Chat::Tools::SearchMemory].include?(t)
            end
            @saved_tools = @session.chat.instance_variable_get(:@tools)
            @session.chat.instance_variable_set(:@tools, read_only_tools || [])
            chat_log.info 'plan_mode enabled'
            out.success('Plan mode ON — read-only (no writes, edits, or commands)')
          else
            @session.chat.instance_variable_set(:@tools, @saved_tools) if @saved_tools
            @saved_tools = nil
            chat_log.info 'plan_mode disabled'
            out.success('Plan mode OFF — all tools available')
          end
        end

        def handle_agent(task, out)
          unless task && !task.strip.empty?
            out.error('Usage: /agent <task description>')
            return
          end

          require 'legion/cli/chat/subagent'
          result = Chat::Subagent.spawn(
            task:        task.strip,
            model:       @session.model_id,
            on_complete: lambda { |id, res|
              output = res[:output] || res[:error] || 'No output'
              @session.chat.add_message(
                role:    :user,
                content: "Subagent #{id} result:\n\n#{output}"
              )
              puts out.dim("\n  [subagent #{id}] Complete. Results added to context.")
              print prompt_string
            }
          )

          if result[:error]
            out.error(result[:error])
          else
            chat_log.info "subagent_spawn id=#{result[:id]} task_length=#{task.length}"
            out.success("Subagent #{result[:id]} started. Results will appear when done.")
          end
        end

        def handle_agents_status(out)
          require 'legion/cli/chat/subagent'
          agents = Chat::Subagent.running
          if agents.empty?
            out.warn('No subagents running.')
            return
          end

          out.header("Running Subagents (#{agents.length})")
          agents.each do |a|
            elapsed = a[:elapsed].round(1)
            puts "  #{a[:id]}  #{elapsed}s  #{a[:task][0..60]}"
          end
        end

        def handle_at_mention(input, out)
          require 'legion/cli/chat/agent_delegator'
          parsed = Chat::AgentDelegator.parse(input)
          return false unless parsed

          Chat::AgentDelegator.dispatch(
            agent_name: parsed[:agent_name],
            task:       parsed[:task],
            session:    @session,
            out:        out,
            chat_log:   chat_log
          )
          true
        end

        def load_custom_agents
          require 'legion/cli/chat/agent_registry'
          agents = Chat::AgentRegistry.load_agents
          return if agents.empty?

          names = agents.keys.join(', ')
          @session.chat.add_message(
            role:    :user,
            content: "Available custom agents: #{names}. Use @name to delegate tasks to them."
          )
        end

        def load_memory_context
          require 'legion/cli/chat/memory_store'
          context = Chat::MemoryStore.load_context
          return unless context

          @session.chat.add_message(
            role:    :user,
            content: "The following is persistent memory from previous sessions:\n\n#{context}\n\nUse this context as needed."
          )
        end

        def handle_rewind(arg, out)
          require 'legion/cli/chat/checkpoint'
          if Chat::Checkpoint.entries.none?
            out.warn('No checkpoints available to rewind.')
            return
          end

          if arg.nil? || arg.strip.empty?
            restored = Chat::Checkpoint.rewind(1)
          elsif arg.strip.match?(/\A\d+\z/)
            restored = Chat::Checkpoint.rewind(arg.strip.to_i)
          else
            entry = Chat::Checkpoint.rewind_file(arg.strip)
            restored = entry ? [entry] : []
          end

          if restored.empty?
            out.warn('Nothing to rewind.')
          else
            restored.each do |e|
              label = e.existed ? 'restored' : 'deleted (was new)'
              puts out.dim("  #{File.basename(e.path)}: #{label}")
            end
            chat_log.info "rewind count=#{restored.length}"
            out.success("Rewound #{restored.length} edit(s)")
          end
        end

        def show_session_stats(out)
          s = @session.stats
          elapsed = @session.elapsed.round(1)
          details = {
            'Messages' => "#{s[:messages_sent]} sent, #{s[:messages_received]} received",
            'Model'    => @session.model_id,
            'Duration' => "#{elapsed}s"
          }
          details['Input tokens']  = s[:input_tokens].to_s  if s[:input_tokens]
          details['Output tokens'] = s[:output_tokens].to_s if s[:output_tokens]
          cost = @session.estimated_cost
          details['Est. cost'] = format('$%.4f', cost) if cost.positive?
          out.detail(details)
        end

        def restore_session(out)
          require 'legion/cli/chat/session_store'
          if options[:continue]
            name = Chat::SessionStore.latest
            @session_name = name
          elsif options[:resume]
            name = options[:resume]
            @session_name = name
          elsif options[:fork]
            name = options[:fork]
            @session_name = nil # fork: save as new on exit
          end

          data = Chat::SessionStore.load(name)
          Chat::SessionStore.restore(@session, data)
          msg_count = data[:messages]&.length || 0
          label = options[:fork] ? 'Forked from' : 'Resumed'
          out.success("#{label} session: #{name} (#{msg_count} messages)")
          chat_log.info "session_restore name=#{name} messages=#{msg_count} mode=#{options[:fork] ? 'fork' : 'resume'}"
        end

        def auto_save_session(out)
          return if @auto_saved
          return if options[:incognito]
          return unless @session
          return if @session.stats[:messages_sent].zero?

          @auto_saved = true
          require 'legion/cli/chat/session_store'
          name = @session_name || "auto-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
          path = Chat::SessionStore.save(@session, name)
          chat_log.info "auto_save name=#{name} path=#{path}"
          out&.dim("  Session saved: #{name}")&.then { |msg| puts msg }
        rescue StandardError => e
          chat_log&.error("auto_save_failed: #{e.message}")
        end
      end
    end
  end
end
