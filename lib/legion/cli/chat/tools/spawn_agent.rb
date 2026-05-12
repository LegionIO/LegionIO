# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SpawnAgent < Legion::Tools::Base
          tool_name 'legion.spawn_agent'
          description 'Spawn a background subagent to work on a task independently. ' \
                      'The subagent runs in a separate process with its own context. ' \
                      'Results are injected back into the conversation when complete.'
          input_schema({
                         type:       'object',
                         properties: {
                           task:  { type: 'string', description: 'The task description for the subagent' },
                           model: { type: 'string', description: 'Model to use (optional, inherits parent)' }
                         },
                         required:   ['task']
                       })

          def self.call(task:, model: nil)
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
            Legion::Logging.warn("SpawnAgent#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error spawning subagent: #{e.message}"
          end

          def self.notify_complete(agent_id, result)
            # Result is available via Subagent.running or injected by the REPL loop
            output = result[:output] || result[:error] || 'No output'
            warn "\n  [subagent #{agent_id}] Complete: #{output.lines.first&.strip}"
          end
        end
      end
    end
  end
end
