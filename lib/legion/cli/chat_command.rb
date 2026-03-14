# frozen_string_literal: true

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
      class_option :system,     type: :string,  desc: 'System prompt override'

      autoload :Session, 'legion/cli/chat/session'

      desc 'interactive', 'Start interactive AI conversation'
      def interactive
        out = formatter
        setup_connection

        chat_obj = create_chat
        system_prompt = build_system_prompt
        @session = Chat::Session.new(chat: chat_obj, system_prompt: system_prompt)

        out.header("Legion AI Chat (#{@session.model_id})")
        puts out.dim('  Type /help for commands, /quit to exit')
        puts

        repl_loop(out)
      rescue CLI::Error => e
        out.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end
      default_task :interactive

      desc 'prompt TEXT', 'Send a single prompt (headless mode)'
      option :output_format, type: :string, default: 'text', desc: 'Output format: text, json'
      option :max_turns, type: :numeric, default: 10, desc: 'Maximum tool-use turns'
      def prompt(text)
        out = formatter
        out.warn("Headless mode not yet implemented. Prompt: #{text}")
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

        def create_chat
          opts = {}
          opts[:model]    = options[:model]           if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]
          Legion::LLM.chat(**opts)
        end

        def build_system_prompt
          return options[:system] if options[:system]

          parts = []
          parts << 'You are Legion, an AI assistant powered by the LegionIO framework.'
          parts << 'You have access to tools for file operations, shell commands, and search.'
          parts << 'Be concise and helpful. Use markdown formatting.'

          %w[LEGION.md CLAUDE.md].each do |name|
            path = File.join(Dir.pwd, name)
            if File.exist?(path)
              content = File.read(path, encoding: 'utf-8')
              parts << "\n# Project Context (#{name})\n#{content}"
              break
            end
          end

          parts.join("\n\n")
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

            begin
              response = @session.send_message(stripped) do |chunk|
                print chunk.content if chunk.content
              end
              puts
              puts
            rescue StandardError => e
              puts
              out.error("LLM error: #{e.message}")
              puts
            end
          end

          puts
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

        def show_help(out)
          out.header('Chat Commands')
          out.detail({
            '/help'    => 'Show this help',
            '/quit'    => 'Exit chat',
            '/cost'    => 'Show session stats',
            '/clear'   => 'Clear conversation history',
            '/model X' => 'Switch model'
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
