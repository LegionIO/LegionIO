# frozen_string_literal: true

module Legion
  module CLI
    class Acp < Thor
      def self.exit_on_failure?
        true
      end

      desc 'stdio', 'Start ACP agent with stdio transport (default)'
      def stdio
        require 'legion/extensions/acp'

        transport = Legion::Extensions::Acp::Transport::Stdio.new
        agent     = Legion::Extensions::Acp::Runners::Agent.new(transport: transport)

        transport.log('LegionIO ACP agent started (stdio)')

        setup_llm if llm_available?

        transport.run { |msg| agent.dispatch(msg) }
      end

      default_command :stdio

      no_commands do
        private

        def llm_available?
          require 'legion/llm'
          true
        rescue LoadError
          false
        end

        def setup_llm
          require 'legion/cli/connection'
          Connection.ensure_settings
          Connection.ensure_llm
        rescue StandardError => e
          warn("[lex-acp] LLM setup failed: #{e.message} — running without prompt support")
        end
      end
    end
  end
end
