# frozen_string_literal: true

require 'monitor'

module Legion
  module CLI
    class Chat
      module TUI
        # Scrollable output pane that accumulates messages and tool results.
        # Renders a window of visible lines based on scroll offset and pane height.
        # Thread-safe: LLM streaming thread writes, main thread reads for rendering.
        class OutputPane
          include MonitorMixin

          PURPLE = "\e[38;2;127;119;221m"
          DIM = "\e[2m"
          BOLD = "\e[1m"
          YELLOW = "\e[33m"
          GREEN = "\e[32m"
          RED = "\e[31m"
          RESET = "\e[0m"

          def initialize
            super # MonitorMixin
            @lines = []
            @scroll_offset = 0
            @streaming_buffer = String.new
            @auto_scroll = true
          end

          def add_message(role, text)
            synchronize do
              case role
              when :user
                @lines << "#{PURPLE}#{BOLD}you#{RESET} #{DIM}>#{RESET} #{text}"
              when :assistant
                text.to_s.lines.each { |line| @lines << line.chomp }
              when :system
                @lines << "#{DIM}#{text}#{RESET}"
              end
              @lines << ''
              pin_to_bottom if @auto_scroll
            end
          end

          def begin_response
            synchronize do
              @lines << "#{PURPLE}#{BOLD}legion#{RESET} #{DIM}>#{RESET} "
              @streaming_buffer = String.new
              pin_to_bottom if @auto_scroll
            end
          end

          # Append a streaming chunk (delta only, not cumulative)
          def append_chunk(text)
            return if text.nil? || text.empty?

            synchronize do
              @streaming_buffer << text

              header_idx = @lines.rindex { |l| l.include?("legion#{RESET} #{DIM}>") }
              if header_idx
                @lines.slice!((header_idx + 1)..)
                @streaming_buffer.lines.each { |line| @lines << line.chomp }
              end

              pin_to_bottom if @auto_scroll
            end
          end

          def end_response(rendered_text)
            synchronize do
              header_idx = @lines.rindex { |l| l.include?("legion#{RESET} #{DIM}>") }
              if header_idx
                @lines.slice!((header_idx + 1)..)
                rendered_text.to_s.lines.each { |line| @lines << line.chomp }
              end
              @lines << ''
              @streaming_buffer = String.new
              pin_to_bottom if @auto_scroll
            end
          end

          def add_tool_call(name, args_summary)
            synchronize do
              @lines << "  #{DIM}[tool] #{name}(#{args_summary})#{RESET}"
              pin_to_bottom if @auto_scroll
            end
          end

          def add_tool_result(preview)
            synchronize do
              @lines << "  #{DIM}[result] #{preview}#{RESET}"
              pin_to_bottom if @auto_scroll
            end
          end

          def add_error(message)
            synchronize do
              @lines << "#{RED}Error: #{message}#{RESET}"
              @lines << ''
              pin_to_bottom if @auto_scroll
            end
          end

          def add_info(text)
            synchronize do
              @lines << "#{DIM}#{text}#{RESET}"
              pin_to_bottom if @auto_scroll
            end
          end

          # Add a pre-formatted line (no extra styling)
          def add_raw(text)
            synchronize do
              @lines << text.to_s
              pin_to_bottom if @auto_scroll
            end
          end

          def clear
            synchronize do
              @lines.clear
              @scroll_offset = 0
              @auto_scroll = true
              @streaming_buffer = String.new
            end
          end

          def scroll_up(lines = 3)
            synchronize do
              @auto_scroll = false
              @scroll_offset = (@scroll_offset + lines).clamp(0, [@lines.length - 1, 0].max)
            end
          end

          def scroll_down(lines = 3)
            synchronize do
              @scroll_offset = (@scroll_offset - lines).clamp(0, @scroll_offset)
              @auto_scroll = true if @scroll_offset.zero?
            end
          end

          def scroll_to_bottom
            synchronize do
              @scroll_offset = 0
              @auto_scroll = true
            end
          end

          def render(width, height)
            synchronize do
              return Array.new(height, '') if @lines.empty?

              total = @lines.length
              start_idx = if @auto_scroll || @scroll_offset.zero?
                            [total - height, 0].max
                          else
                            [total - height - @scroll_offset, 0].max
                          end

              visible = @lines[start_idx, height] || []

              height.times.map do |i|
                line = visible[i] || ''
                truncate_to_width(line, width)
              end
            end
          end

          def line_count
            synchronize { @lines.length }
          end

          private

          def pin_to_bottom
            @scroll_offset = 0
          end

          # ANSI-aware truncation: walks the string tracking visible character
          # count vs. escape sequences so we never split an escape mid-sequence.
          def truncate_to_width(line, width) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            visible_count = 0
            i = 0
            result = String.new

            while i < line.length
              if line[i] == "\e"
                # Copy the full escape sequence without counting visible chars
                j = i + 1
                if j < line.length && line[j] == '['
                  j += 1
                  j += 1 while j < line.length && line[j].ord < 0x40 # rubocop:disable Metrics/BlockNesting
                  j += 1 if j < line.length # final byte
                elsif j < line.length && line[j] == ']'
                  # OSC sequence: skip to ST (\e\\)
                  j += 1
                  j += 1 while j < line.length && !(line[j] == "\e" && j + 1 < line.length && line[j + 1] == '\\') # rubocop:disable Metrics/BlockNesting
                  j += 2 if j < line.length # skip \e\\
                end
                result << line[i...j]
                i = j
              else
                break if visible_count >= width

                result << line[i]
                visible_count += 1
                i += 1
              end
            end

            # Append RESET if we truncated styled text
            result << RESET if visible_count >= width && i < line.length

            result
          end

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').gsub(/\e\].*?\e\\/, '')
          end
        end
      end
    end
  end
end
