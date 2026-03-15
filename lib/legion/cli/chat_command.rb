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

      autoload :Session, 'legion/cli/chat/session'

      desc 'interactive', 'Start interactive AI conversation'
      def interactive
        out = formatter
        setup_connection

        chat_obj = create_chat
        configure_permissions(:interactive)
        system_prompt = build_system_prompt
        @session = Chat::Session.new(chat: chat_obj, system_prompt: system_prompt)

        out.header("Legion AI Chat (#{@session.model_id})")
        puts out.dim('  Type /help for commands, /quit to exit')
        puts

        repl_loop(out)
      rescue Interrupt
        puts
        puts out.dim('Interrupted.')
        show_session_stats(out) if @session
      rescue CLI::Error => e
        out.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end
      default_task :interactive

      desc 'prompt TEXT', 'Send a single prompt and exit (headless mode)'
      option :output_format, type: :string, default: 'text', desc: 'Output format: text, json'
      option :max_turns, type: :numeric, default: 10, desc: 'Maximum tool-use turns'
      def prompt(text)
        out = formatter
        setup_connection

        text = combine_with_stdin(text)
        raise CLI::Error, 'No prompt text provided. Pass text as argument or pipe via stdin.' if text.empty?

        chat_obj = create_chat
        configure_permissions(:headless)
        system_prompt = build_system_prompt
        session = Chat::Session.new(chat: chat_obj, system_prompt: system_prompt)

        response = if options[:output_format] == 'json'
                     session.send_message(text)
                   else
                     session.send_message(text) { |chunk| print chunk.content if chunk.content }
                   end

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
        out.error(e.message)
        raise SystemExit, 1
      rescue StandardError => e
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

            print out.colorize('legion', :green)
            print out.dim(' > ')

            buffer = String.new
            @session.send_message(
              stripped,
              on_tool_call:   lambda { |tc|
                puts out.dim("  [tool] #{tc.name}(#{tc.arguments.keys.join(', ')})")
              },
              on_tool_result: lambda { |tr|
                result_preview = tr.to_s.lines.first(3).join.rstrip
                puts out.dim("  [result] #{result_preview}")
              }
            ) do |chunk|
              buffer << chunk.content if chunk.content
            end
            print render_response(buffer, out)
            puts
            puts
          rescue Interrupt
            puts
            next
          rescue StandardError => e
            puts
            out.error("LLM error: #{e.message}")
            puts
          end

          puts
          puts out.dim('Goodbye.')
          show_session_stats(out)
        end

        def prompt_string
          "\001\e[36m\002you\001\e[0m\002 > "
        end

        def handle_slash_command(input, out)
          cmd, *args = input.split(' ', 2)
          case cmd.downcase
          when '/quit', '/exit', '/q'
            show_session_stats(out)
            raise SystemExit, 0
          when '/help', '/h'
            show_help(out)
          when '/cost'
            show_session_stats(out)
          when '/clear'
            @session.chat.reset_messages!
            out.success('Conversation cleared')
          when '/save'
            handle_save(args.first, out)
          when '/load'
            handle_load(args.first, out)
          when '/sessions'
            handle_sessions(out)
          when '/model'
            if args.first
              @session.chat.with_model(args.first)
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
                       '/help'      => 'Show this help',
                       '/quit'      => 'Exit chat',
                       '/cost'      => 'Show session stats',
                       '/clear'     => 'Clear conversation history',
                       '/save NAME' => 'Save session to disk',
                       '/load NAME' => 'Load a saved session',
                       '/sessions'  => 'List saved sessions',
                       '/model X'   => 'Switch model'
                     })
          puts
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
          out.detail(details)
        end
      end
    end
  end
end
