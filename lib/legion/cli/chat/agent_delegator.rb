# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module AgentDelegator
        module_function

        def delegate?(input)
          return :at_mention if input.match?(/\A@\w+\s/)
          return :slash if input.match?(%r{\A/agent\s+\w+\s})

          false
        end

        def parse(input)
          case delegate?(input)
          when :at_mention
            match = input.match(/\A@(\w+)\s+(.+)/m)
            return nil unless match

            { agent_name: match[1], task: match[2].strip }
          when :slash
            match = input.match(%r{\A/agent\s+(\w+)\s+(.+)}m)
            return nil unless match

            { agent_name: match[1], task: match[2].strip }
          end
        end

        def dispatch(agent_name:, task:, session:, out:, chat_log: nil)
          require 'legion/cli/chat/agent_registry'
          agent = AgentRegistry.find(agent_name)
          unless agent
            out.error("Unknown agent: @#{agent_name}. Available: #{AgentRegistry.names.join(', ')}")
            return
          end

          chat_log&.info("agent_delegate name=#{agent_name} task_length=#{task.length}")

          require 'legion/cli/chat/subagent'
          prompt = build_agent_prompt(agent, task)

          result = Subagent.spawn(
            task:        prompt,
            model:       agent[:model],
            on_complete: lambda { |_id, res|
              output = res[:output] || res[:error] || 'No output'
              session.chat.add_message(
                role:    :user,
                content: "@#{agent_name} result:\n\n#{output}"
              )
              puts out.dim("\n  [@#{agent_name}] Complete. Results added to context.")
            }
          )

          if result[:error]
            out.error(result[:error])
          else
            out.success("Delegated to @#{agent_name} (#{result[:id]})")
          end
        end

        def build_agent_prompt(agent, task)
          parts = []
          parts << agent[:system_prompt] if agent[:system_prompt]
          parts << "Task: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
end
