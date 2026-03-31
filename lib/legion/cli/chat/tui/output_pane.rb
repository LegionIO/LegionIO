# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module TUI
        # Scrollable output pane that accumulates messages and tool results.
        # Renders a window of visible lines based on scroll offset and pane height.
        class OutputPane
          PURPLE = "\e[38;2;127;119;221m"
          DIM = "\e[2m"
          BOLD = "\e[1m"
          YELLOW = "\e[33m"
          GREEN = "\e[32m"
          RED = "\e[31m"
          RESET = "\e[0m"

          def initialize
            @lines = []           # All accumulated output lines (raw strings with ANSI)
            @scroll_offset = 0    # 0 = pinned to bottom (auto-scroll), >0 = scrolled up
            @streaming_buffer = String.new
            @auto_scroll = true
          end

          # Add a complete message block (user or assistant)
          def add_message(role, text)
            case role
            when :user
              @lines << "#{PURPLE}#{BOLD}you#{RESET} #{DIM}>#{RESET} #{text}"
            when :assistant
              # Assistant messages may be multi-line; wrap each line
              text.to_s.lines.each { |line| @lines << line.chomp }
            when :system
              @lines << "#{DIM}#{text}#{RESET}"
            end
            @lines << '' # blank line spacer
            pin_to_bottom if @auto_scroll
          end

          # Start streaming a response — show the header
          def begin_response
            @lines << "#{PURPLE}#{BOLD}legion#{RESET} #{DIM}>#{RESET} "
            @streaming_buffer = String.new
            pin_to_bottom if @auto_scroll
          end

          # Append a streaming chunk to the current response
          def append_chunk(text)
            return if text.nil? || text.empty?

            @streaming_buffer << text

            # Replace the last line(s) of the response with the full rendered buffer
            # Remove previous streaming lines (everything after the last "legion >" header)
            # Find the response header
            header_idx = @lines.rindex { |l| l.include?("legion#{RESET} #{DIM}>") }
            if header_idx
              @lines.slice!(header_idx + 1..)
              # Re-add all lines from the streaming buffer
              @streaming_buffer.lines.each { |line| @lines << line.chomp }
            end

            pin_to_bottom if @auto_scroll
          end

          # Finalize the current streaming response with the full rendered text
          def end_response(rendered_text)
            header_idx = @lines.rindex { |l| l.include?("legion#{RESET} #{DIM}>") }
            if header_idx
              @lines.slice!(header_idx + 1..)
              rendered_text.to_s.lines.each { |line| @lines << line.chomp }
            end
            @lines << '' # spacer
            @streaming_buffer = String.new
            pin_to_bottom if @auto_scroll
          end

          # Add a tool call notification
          def add_tool_call(name, args_summary)
            @lines << "  #{DIM}[tool] #{name}(#{args_summary})#{RESET}"
            pin_to_bottom if @auto_scroll
          end

          # Add a tool result
          def add_tool_result(preview)
            @lines << "  #{DIM}[result] #{preview}#{RESET}"
            pin_to_bottom if @auto_scroll
          end

          # Add an error message
          def add_error(message)
            @lines << "#{RED}Error: #{message}#{RESET}"
            @lines << ''
            pin_to_bottom if @auto_scroll
          end

          # Add an info/banner line
          def add_info(text)
            @lines << "#{DIM}#{text}#{RESET}"
            pin_to_bottom if @auto_scroll
          end

          def scroll_up(n = 3)
            @auto_scroll = false
            @scroll_offset = [@scroll_offset + n, [@lines.length - 1, 0].max].min
          end

          def scroll_down(n = 3)
            @scroll_offset = [@scroll_offset - n, 0].max
            @auto_scroll = true if @scroll_offset.zero?
          end

          def scroll_to_bottom
            @scroll_offset = 0
            @auto_scroll = true
          end

          # Render visible lines for the given pane height, truncating each to width.
          def render(width, height)
            return Array.new(height, '') if @lines.empty?

            # Calculate the visible window
            total = @lines.length
            if @auto_scroll || @scroll_offset.zero?
              # Show the last `height` lines
              start_idx = [total - height, 0].max
            else
              start_idx = [total - height - @scroll_offset, 0].max
            end

            visible = @lines[start_idx, height] || []

            # Pad to fill the pane and truncate long lines
            height.times.map do |i|
              line = visible[i] || ''
              truncate_to_width(line, width)
            end
          end

          def line_count
            @lines.length
          end

          private

          def pin_to_bottom
            @scroll_offset = 0
          end

          def truncate_to_width(line, width)
            # We need to count visible characters (excluding ANSI escapes)
            visible_len = strip_ansi(line).length
            return line if visible_len <= width

            # Truncate by visible characters — this is approximate for ANSI strings
            # A proper implementation would walk char-by-char tracking ANSI state
            line[0, width + (line.length - visible_len)]
          end

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').gsub(/\e\].*?\e\\/, '')
          end
        end
      end
    end
  end
end
