# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      class Session
        attr_reader :chat, :stats

        def initialize(chat:, system_prompt: nil)
          @chat = chat
          @chat.with_instructions(system_prompt) if system_prompt
          @stats = {
            messages_sent:     0,
            messages_received: 0,
            started_at:        Time.now
          }
        end

        def send_message(message, on_tool_call: nil, on_tool_result: nil, &block)
          @stats[:messages_sent] += 1

          @chat.on_tool_call { |tc| on_tool_call&.call(tc) }
          @chat.on_tool_result { |tr| on_tool_result&.call(tr) }

          response = @chat.ask(message, &block)
          @stats[:messages_received] += 1

          # Track token usage if available
          if response.respond_to?(:input_tokens)
            @stats[:input_tokens]  = (@stats[:input_tokens] || 0) + (response.input_tokens || 0)
            @stats[:output_tokens] = (@stats[:output_tokens] || 0) + (response.output_tokens || 0)
          end

          response
        end

        def model_id
          @chat.model&.id
        rescue StandardError
          'unknown'
        end

        def elapsed
          Time.now - @stats[:started_at]
        end
      end
    end
  end
end
