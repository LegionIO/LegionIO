# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module TUI
        # Character-by-character input handling with history, paste support,
        # and multi-line editing. Renders into a fixed screen region.
        #
        # Handles raw key events — does NOT use Reline or TTY::Reader's read_line.
        class InputBar
          PURPLE = "\e[38;2;127;119;221m"
          DIM = "\e[2m"
          RESET = "\e[0m"

          attr_reader :cursor_col

          def initialize(prompt_label: 'you', completions: [])
            @prompt_label = prompt_label
            @buffer = String.new
            @cursor_pos = 0          # position within @buffer
            @history = []
            @history_index = nil
            @history_stash = nil     # saves current buffer when browsing history
            @completions = completions
            @continuation = false    # true when in multi-line (backslash) mode
            @lines = ['']            # multi-line buffer (for paste support)
            @current_line = 0
          end

          # Process a single key event. Returns:
          #   [:submit, text]  — user pressed Enter with complete input
          #   :handled         — key was consumed, re-render needed
          #   :pass            — key should be handled by the outer app (e.g., page up/down)
          def handle_key(key)
            case key
            when :enter, :return
              return handle_enter
            when :backspace, :delete_back
              return handle_backspace
            when :delete
              return handle_delete
            when :left, :arrow_left
              @cursor_pos = [@cursor_pos - 1, 0].max
              return :handled
            when :right, :arrow_right
              @cursor_pos = [@cursor_pos + 1, @buffer.length].min
              return :handled
            when :up, :arrow_up
              return handle_history_prev
            when :down, :arrow_down
              return handle_history_next
            when :home, :ctrl_a
              @cursor_pos = 0
              return :handled
            when :end, :ctrl_e
              @cursor_pos = @buffer.length
              return :handled
            when :ctrl_u
              @buffer = @buffer[@cursor_pos..] || ''
              @cursor_pos = 0
              return :handled
            when :ctrl_k
              @buffer = @buffer[0...@cursor_pos] || ''
              return :handled
            when :ctrl_w
              return handle_delete_word
            when :ctrl_c
              @buffer = String.new
              @cursor_pos = 0
              @continuation = false
              return :handled
            when :tab
              return handle_tab
            when :page_up, :page_down, :ctrl_d
              return :pass
            else
              # Printable character or paste
              if key.is_a?(String)
                return handle_paste(key) if key.length > 1
                return handle_char(key)
              end
              :handled
            end
          end

          def render(width, prompt_width: nil)
            prompt = build_prompt
            pw = prompt_width || strip_ansi(prompt).length
            available = width - pw

            # For now, single-line display with horizontal scroll
            visible_start = if @cursor_pos >= available
                              @cursor_pos - available + 1
                            else
                              0
                            end
            visible_text = @buffer[visible_start, available] || ''

            # Build the display lines
            lines = []
            lines << "#{prompt}#{visible_text}"

            # Continuation indicator if in multi-line mode
            if @continuation
              lines << "#{DIM} ...#{RESET} "
            end

            # Pad to minimum height
            while lines.length < 3
              lines << ''
            end

            @cursor_col = pw + (@cursor_pos - visible_start)
            lines
          end

          def clear
            @buffer = String.new
            @cursor_pos = 0
            @continuation = false
          end

          def set_prompt_label(label)
            @prompt_label = label
          end

          def buffer_content
            @buffer.dup
          end

          def empty?
            @buffer.strip.empty?
          end

          private

          def build_prompt
            "#{PURPLE}#{@prompt_label}#{RESET} #{DIM}>#{RESET} "
          end

          def handle_enter
            text = @buffer.strip

            # Multi-line continuation with trailing backslash
            if text.end_with?('\\')
              @buffer << "\n"
              @cursor_pos = @buffer.length
              @continuation = true
              return :handled
            end

            return :handled if text.empty?

            # Finalize
            result = text.gsub(/\\\n/, "\n")
            @history << result unless result.empty? || @history.last == result
            @history_index = nil
            @history_stash = nil
            @buffer = String.new
            @cursor_pos = 0
            @continuation = false
            [:submit, result]
          end

          def handle_backspace
            return :handled if @cursor_pos.zero?

            @buffer = @buffer[0...(@cursor_pos - 1)] + (@buffer[@cursor_pos..] || '')
            @cursor_pos -= 1
            :handled
          end

          def handle_delete
            return :handled if @cursor_pos >= @buffer.length

            @buffer = @buffer[0...@cursor_pos] + (@buffer[(@cursor_pos + 1)..] || '')
            :handled
          end

          def handle_delete_word
            return :handled if @cursor_pos.zero?

            # Delete backward to previous word boundary
            pos = @cursor_pos - 1
            pos -= 1 while pos.positive? && @buffer[pos] == ' '
            pos -= 1 while pos.positive? && @buffer[pos] != ' '
            pos += 1 if @buffer[pos] == ' '
            @buffer = (@buffer[0...pos] || '') + (@buffer[@cursor_pos..] || '')
            @cursor_pos = pos
            :handled
          end

          def handle_char(ch)
            @buffer = @buffer[0...@cursor_pos] + ch + (@buffer[@cursor_pos..] || '')
            @cursor_pos += 1
            :handled
          end

          def handle_paste(text)
            # Treat pasted text as a single input block (fixes the multi-line paste bug)
            # Replace newlines with literal newlines in buffer
            @buffer = @buffer[0...@cursor_pos] + text + (@buffer[@cursor_pos..] || '')
            @cursor_pos += text.length
            :handled
          end

          def handle_history_prev
            return :handled if @history.empty?

            if @history_index.nil?
              @history_stash = @buffer.dup
              @history_index = @history.length - 1
            elsif @history_index.positive?
              @history_index -= 1
            else
              return :handled
            end

            @buffer = @history[@history_index].dup
            @cursor_pos = @buffer.length
            :handled
          end

          def handle_history_next
            return :handled if @history_index.nil?

            if @history_index < @history.length - 1
              @history_index += 1
              @buffer = @history[@history_index].dup
            else
              @buffer = @history_stash || ''
              @history_index = nil
              @history_stash = nil
            end

            @cursor_pos = @buffer.length
            :handled
          end

          def handle_tab
            return :handled if @completions.empty?

            # Simple prefix completion
            prefix = @buffer[0...@cursor_pos]
            matches = @completions.select { |c| c.start_with?(prefix) }

            if matches.length == 1
              @buffer = matches.first + ' '
              @cursor_pos = @buffer.length
            end

            :handled
          end

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').gsub(/\e\].*?\e\\/, '')
          end
        end
      end
    end
  end
end
