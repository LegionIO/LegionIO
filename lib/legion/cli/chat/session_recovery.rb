# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module SessionRecovery
        STATES = %i[none interrupted_prompt interrupted_turn].freeze

        class << self
          def classify(messages)
            cleaned = filter_artifacts(messages)
            return :none if cleaned.empty?

            last = cleaned.last
            role = msg_role(last)

            case role
            when 'user' then :interrupted_prompt
            when 'tool_result', 'tool' then :interrupted_turn
            when 'assistant'
              tool_calls = last.is_a?(Hash) ? (last[:tool_calls] || last['tool_calls']) : nil
              tool_calls.is_a?(Array) && tool_calls.any? ? :interrupted_turn : :none
            else :none
            end
          end

          def recover(messages)
            cleaned = filter_artifacts(messages)
            state = classify(cleaned)

            case state
            when :none
              { state: :none, messages: cleaned, recovery_message: nil }
            when :interrupted_prompt
              msg = 'Continue from where you left off. The previous session was interrupted.'
              { state: :interrupted_prompt, messages: cleaned, recovery_message: msg }
            when :interrupted_turn
              tool_name = detect_interrupted_tool(cleaned)
              msg = 'Continue from where you left off. The previous session was interrupted'
              msg += " during tool execution (#{tool_name})" if tool_name
              msg += '.'
              repaired = repair_orphaned_tool_use(cleaned)
              { state: :interrupted_turn, messages: repaired, recovery_message: msg }
            end
          end

          private

          def filter_artifacts(messages)
            messages.reject do |msg|
              role = msg_role(msg)
              content = msg_content(msg)

              next true if role == 'assistant' && thinking_only?(msg)
              next true if role == 'assistant' && whitespace_only?(content)

              false
            end
          end

          def thinking_only?(msg)
            content = msg_content(msg)
            return false unless content.nil? || content.to_s.strip.empty?

            tool_calls = msg.is_a?(Hash) ? (msg[:tool_calls] || msg['tool_calls']) : nil
            tool_calls.nil? || (tool_calls.is_a?(Array) && tool_calls.empty?)
          end

          def whitespace_only?(content)
            return true if content.nil?

            content.to_s.strip.empty?
          end

          def msg_role(msg)
            if msg.is_a?(Hash)
              (msg[:role] || msg['role']).to_s
            elsif msg.respond_to?(:role)
              msg.role.to_s
            else
              ''
            end
          end

          def msg_content(msg)
            if msg.is_a?(Hash)
              msg[:content] || msg['content']
            elsif msg.respond_to?(:content)
              msg.content
            end
          end

          def detect_interrupted_tool(messages)
            reversed = messages.reverse
            reversed.each do |msg|
              role = msg_role(msg)
              next unless role == 'assistant'

              tool_calls = msg.is_a?(Hash) ? (msg[:tool_calls] || msg['tool_calls']) : nil
              next unless tool_calls.is_a?(Array) && tool_calls.any?

              first_tool = tool_calls.first
              return first_tool[:name] || first_tool['name'] if first_tool.is_a?(Hash)
            end
            nil
          end

          def repair_orphaned_tool_use(messages)
            return messages if messages.empty?

            last = messages.last
            role = msg_role(last)

            return messages[0...-1] if %w[tool_result tool].include?(role)

            if role == 'assistant'
              tool_calls = last.is_a?(Hash) ? (last[:tool_calls] || last['tool_calls']) : nil
              return messages[0...-1] if tool_calls.is_a?(Array) && tool_calls.any?
            end

            messages
          end
        end
      end
    end
  end
end
