# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Plan < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Model ID'
      class_option :provider,   type: :string,  desc: 'LLM provider'
      class_option :no_markdown, type: :boolean, default: false, desc: 'Disable markdown rendering'

      desc 'interactive', 'Start plan mode (read-only exploration)'
      def interactive
        out = formatter
        setup_connection

        chat_obj = create_plan_chat
        system_prompt = build_plan_prompt

        require 'legion/cli/chat/session'
        @session = Chat::Session.new(chat: chat_obj, system_prompt: system_prompt)

        out.header("Legion Plan Mode (#{@session.model_id})")
        puts out.dim('  Read-only exploration. No file writes or shell commands.')
        puts out.dim('  Type /save to save plan, /quit to exit')
        puts

        plan_repl(out)
      rescue Interrupt
        puts
        puts out.dim('Interrupted.')
      ensure
        Connection.shutdown
      end
      default_task :interactive

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

        def create_plan_chat
          opts = {}
          opts[:model]    = options[:model] if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]

          require 'legion/cli/chat/tools/read_file'
          require 'legion/cli/chat/tools/search_files'
          require 'legion/cli/chat/tools/search_content'

          chat = Legion::LLM.chat(**opts)
          chat.with_tools(
            Chat::Tools::ReadFile,
            Chat::Tools::SearchFiles,
            Chat::Tools::SearchContent
          )
          chat
        end

        def build_plan_prompt
          require 'legion/cli/chat/context'
          base = Chat::Context.to_system_prompt(Dir.pwd)
          <<~PROMPT
            #{base}

            You are in PLAN MODE. You can ONLY read files and search the codebase.
            You CANNOT write files, edit files, or run shell commands.

            Your job is to:
            1. Explore the codebase to understand the current state
            2. Ask clarifying questions about what the user wants to build
            3. Produce a structured implementation plan as a markdown document

            When the user is satisfied with the plan, they will use /save to save it.
            Output the final plan in markdown format with clear task breakdowns.
          PROMPT
        end

        def render_response(text, out)
          return text if options[:no_markdown] || options[:no_color]

          require 'legion/cli/chat/markdown_renderer'
          Chat::MarkdownRenderer.render(text, color: out.color_enabled)
        rescue LoadError => e
          Legion::Logging.debug("PlanCommand#render_response markdown_renderer not available: #{e.message}") if defined?(Legion::Logging)
          text
        end

        def plan_repl(out)
          require 'reline'
          @plan_buffer = String.new

          loop do
            line = Reline.readline("\001\e[38;2;100;200;100m\002plan\001\e[0m\002 > ", true)
            break if line.nil?

            stripped = line.strip
            next if stripped.empty?

            case stripped.downcase
            when '/quit', '/exit', '/q'
              break
            when '/save'
              save_plan(out)
              next
            when '/help'
              show_plan_help(out)
              next
            end

            print out.colorize('legion', :title)
            print out.dim(' > ')

            buffer = String.new
            @session.send_message(stripped) { |chunk| buffer << chunk.content if chunk.content }
            @plan_buffer << "\n\n#{buffer}" unless buffer.empty?
            print render_response(buffer, out)
            puts
            puts
          rescue Interrupt
            puts
            next
          rescue StandardError => e
            puts
            out.error("Error: #{e.message}")
            puts
          end

          puts
          puts out.dim('Goodbye.')
        end

        def save_plan(out)
          if @plan_buffer.strip.empty?
            out.warn('No plan content to save. Have a conversation first.')
            return
          end

          require 'fileutils'
          dir = File.join(Dir.pwd, 'docs', 'plans')
          FileUtils.mkdir_p(dir)
          filename = "#{Time.now.strftime('%Y-%m-%d')}-plan.md"
          path = File.join(dir, filename)

          # Avoid overwriting
          counter = 1
          while File.exist?(path)
            filename = "#{Time.now.strftime('%Y-%m-%d')}-plan-#{counter}.md"
            path = File.join(dir, filename)
            counter += 1
          end

          File.write(path, @plan_buffer.strip, encoding: 'utf-8')
          out.success("Plan saved to #{path}")
        end

        def show_plan_help(out)
          out.header('Plan Mode Commands')
          out.detail({
                       '/save' => 'Save the plan to docs/plans/',
                       '/help' => 'Show this help',
                       '/quit' => 'Exit plan mode'
                     })
          puts
          puts out.dim('  Read-only: file reads and searches only. No writes or commands.')
        end
      end
    end
  end
end
