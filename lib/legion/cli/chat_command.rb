# frozen_string_literal: true

module Legion
  module CLI
    class Chat < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,  type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'
      class_option :model,    type: :string,  aliases: ['-m'], desc: 'Model ID (e.g., claude-sonnet-4-6)'
      class_option :provider, type: :string,  desc: 'LLM provider (bedrock, anthropic, openai, gemini, ollama)'
      class_option :system,   type: :string,  desc: 'System prompt override'

      desc 'interactive', 'Start interactive AI conversation'
      def interactive
        out = formatter
        out.header('Legion AI Chat')
        out.warn('Chat not yet implemented — coming soon')
      end
      default_task :interactive

      desc 'prompt TEXT', 'Send a single prompt (headless mode)'
      option :output_format, type: :string, default: 'text', desc: 'Output format: text, json, stream-json'
      option :max_turns, type: :numeric, desc: 'Maximum agentic turns'
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
      end
    end
  end
end
