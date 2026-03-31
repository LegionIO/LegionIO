# frozen_string_literal: true

require 'tty-cursor'
require 'tty-screen'

module Legion
  module CLI
    class Chat
      module TUI
        # Manages the three-region terminal layout with differential rendering.
        #
        # ┌─────────────────────────────────┐
        # │  Output pane (scrollable)       │ rows 0..(height - status_h - input_h - 1)
        # ├─────────────────────────────────┤
        # │  Status bar (1 row)             │ row (height - input_h - 1)
        # ├─────────────────────────────────┤
        # │  Input region (variable height) │ rows (height - input_h)..(height - 1)
        # └─────────────────────────────────┘
        class Screen
          INPUT_MIN_HEIGHT = 3
          STATUS_HEIGHT = 1

          attr_reader :width, :height

          def initialize
            @cursor = TTY::Cursor
            @prev_frame = []
            @dirty = true
            detect_size
          end

          def detect_size
            @height, @width = TTY::Screen.size
            @dirty = true
          end

          def output_height(input_height = INPUT_MIN_HEIGHT)
            @height - STATUS_HEIGHT - [input_height, INPUT_MIN_HEIGHT].max
          end

          def status_row(input_height = INPUT_MIN_HEIGHT)
            @height - [input_height, INPUT_MIN_HEIGHT].max - STATUS_HEIGHT
          end

          def input_start_row(input_height = INPUT_MIN_HEIGHT)
            @height - [input_height, INPUT_MIN_HEIGHT].max
          end

          # Compose a full frame from pane contents and write only changed lines.
          # output_lines: Array[String] — visible lines for the output pane
          # status_line:  String        — the status bar content
          # input_lines:  Array[String] — visible lines for the input region
          def render(output_lines, status_line, input_lines)
            detect_size

            inp_h = [input_lines.length, INPUT_MIN_HEIGHT].max
            out_h = output_height(inp_h)
            s_row = status_row(inp_h)

            # Build the full frame as an array of strings, one per terminal row
            frame = Array.new(@height, '')

            # Output pane — pad or truncate to fill its region
            out_h.times do |i|
              frame[i] = (output_lines[i] || '').to_s
            end

            # Status bar
            frame[s_row] = status_line.to_s

            # Input region
            i_start = input_start_row(inp_h)
            inp_h.times do |i|
              frame[i_start + i] = (input_lines[i] || '').to_s
            end

            write_differential(frame)
            @prev_frame = frame
          end

          # Position the hardware cursor at a specific location (for input editing)
          def position_cursor(col, row)
            $stdout.print @cursor.move_to(col, row)
            $stdout.flush
          end

          def clear
            $stdout.print @cursor.clear_screen
            $stdout.print @cursor.move_to(0, 0)
            $stdout.flush
            @prev_frame = []
          end

          def hide_cursor
            $stdout.print @cursor.hide
          end

          def show_cursor
            $stdout.print @cursor.show
          end

          private

          def write_differential(frame)
            buf = String.new
            frame.each_with_index do |line, row|
              next if @prev_frame[row] == line

              buf << @cursor.move_to(0, row)
              buf << line
              # Clear any remaining characters from the previous frame
              plain_len = strip_ansi(line).length
              buf << (' ' * (@width - plain_len)) if plain_len < @width
            end
            $stdout.print buf
            $stdout.flush
          end

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').gsub(/\e\].*?\e\\/, '')
          end
        end
      end
    end
  end
end
