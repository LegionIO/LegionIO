# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SpawnAgent < RubyLLM::Tool
          description 'Spawn a background subagent to work on a task independently. ' \
                      'The subagent runs in a separate process with its own context. ' \
                      'Results are injected back into the conversation when complete.'
          param :task, type: 'string', desc: 'The task description for the subagent'
          param :model, type: 'string', desc: 'Model to use (optional, inherits parent)', required: false

          def execute(task:, model: nil)
            require 'legion/cli/chat/subagent'
            result = Subagent.spawn(
              task:        task,
              model:       model,
              on_complete: method(:notify_complete)
            )

            if result[:error]
              "Subagent error: #{result[:error]}"
            else
              "Subagent #{result[:id]} started: #{task}"
            end
          rescue StandardError => e
            "Error spawning subagent: #{e.message}"
          end

          private

          def notify_complete(agent_id, result)
            # Result is available via Subagent.running or injected by the REPL loop
            output = result[:output] || result[:error] || 'No output'
            warn "\n  [subagent #{agent_id}] Complete: #{output.lines.first&.strip}"
          end
        end
      end
    end
  end
end
