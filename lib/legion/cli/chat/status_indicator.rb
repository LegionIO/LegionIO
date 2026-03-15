# frozen_string_literal: true

require 'tty-spinner'

module Legion
  module CLI
    class Chat
      class StatusIndicator
        SPINNER_FORMAT = :dots
        PURPLE = "\e[38;2;127;119;221m"
        RESET = "\e[0m"

        def initialize(session)
          @session = session
          @active_spinner = nil
          subscribe_events
        end

        private

        def subscribe_events
          @session.on(:llm_start) { |_payload| start_spinner('thinking...') }
          @session.on(:llm_first_token) { |_payload| stop_spinner }
          @session.on(:llm_complete) { |_payload| stop_spinner }
          @session.on(:tool_start) { |payload| handle_tool_start(payload) }
          @session.on(:tool_complete) { |_payload| stop_spinner }
        end

        def handle_tool_start(payload)
          stop_spinner
          label = if payload[:total] && payload[:total] > 1
                    "[#{payload[:index]}/#{payload[:total]}] running #{payload[:name]}..."
                  else
                    "running #{payload[:name]}..."
                  end
          start_spinner(label)
        end

        def start_spinner(label)
          stop_spinner
          @active_spinner = TTY::Spinner.new(
            "#{PURPLE}:spinner#{RESET} #{label}",
            format:      SPINNER_FORMAT,
            hide_cursor: true,
            output:      $stderr
          )
          @active_spinner.auto_spin
        end

        def stop_spinner
          return unless @active_spinner

          @active_spinner.stop
          @active_spinner = nil
        end
      end
    end
  end
end
