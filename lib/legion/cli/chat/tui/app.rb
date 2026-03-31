# frozen_string_literal: true

require 'io/wait'
require_relative 'screen'
require_relative 'output_pane'
require_relative 'status_bar'
require_relative 'input_bar'

module Legion
  module CLI
    class Chat
      module TUI
        # The main TUI application. Replaces the old Reline-based repl_loop with a
        # raw-mode event loop driving three non-overlapping screen regions.
        #
        # Usage:
        #   app = TUI::App.new(session:, slash_handler:, completions:)
        #   app.run
        class App
          # Key mapping: raw escape sequences → symbolic key names
          KEY_MAP = {
            "\r"      => :enter,
            "\n"      => :enter,
            "\x7F"    => :backspace,
            "\b"      => :backspace,
            "\e[A"    => :up,
            "\e[B"    => :down,
            "\e[C"    => :right,
            "\e[D"    => :left,
            "\e[H"    => :home,
            "\e[F"    => :end,
            "\e[1~"   => :home,
            "\e[4~"   => :end,
            "\e[5~"   => :page_up,
            "\e[6~"   => :page_down,
            "\e[3~"   => :delete,
            "\eOA"    => :up,
            "\eOB"    => :down,
            "\eOC"    => :right,
            "\eOD"    => :left,
            "\eOH"    => :home,
            "\eOF"    => :end,
            "\x01"    => :ctrl_a,
            "\x02"    => :ctrl_b,
            "\x03"    => :ctrl_c,
            "\x04"    => :ctrl_d,
            "\x05"    => :ctrl_e,
            "\x0B"    => :ctrl_k,
            "\x0C"    => :ctrl_l,
            "\x15"    => :ctrl_u,
            "\x17"    => :ctrl_w,
            "\t"      => :tab
          }.freeze

          def initialize(session:, model_id: 'unknown', permissions_mode: 'interactive',
                         slash_handler: nil, completions: [], banner: nil)
            @session = session
            @screen = Screen.new
            @output = OutputPane.new
            @status = StatusBar.new
            @input = InputBar.new(completions: completions)
            @slash_handler = slash_handler
            @running = false
            @streaming = false
            @render_mutex = Mutex.new

            @status.update(model: model_id, permissions_mode: permissions_mode)

            # Wire up session events
            setup_session_events

            # Show banner if provided
            if banner
              banner.to_s.lines.each { |l| @output.add_info(l.chomp) }
              @output.add_info('')
            end
          end

          def run
            @running = true
            @screen.clear
            @screen.hide_cursor

            $stdin.raw do |raw_in|
              render_frame
              @screen.show_cursor

              while @running
                render_frame

                # 50ms timeout during streaming for animation, blocking otherwise
                timeout = @streaming ? 0.05 : 0.1
                raw_key = read_raw_key(raw_in, timeout: timeout)

                if @streaming
                  @status.tick
                  next unless raw_key
                end

                next unless raw_key

                key = normalize_key(raw_key)
                dispatch_key(key)
              end
            end
          rescue Interrupt
            # Ctrl+C during raw mode
          ensure
            @screen.show_cursor
            $stdout.print "\e[0m"
            $stdout.print TTY::Cursor.move_to(0, @screen.height - 1)
            $stdout.print TTY::Cursor.clear_screen_down
            $stdout.flush
          end

          def stop
            @running = false
          end

          private

          def setup_session_events
            @session.on(:llm_start) do |_payload|
              @streaming = true
              @status.update(thinking: true)
            end

            @session.on(:llm_first_token) do |_payload|
              @status.update(thinking: false)
            end

            @session.on(:llm_complete) do |_payload|
              @streaming = false
              @status.update(thinking: false, tool_name: nil)
            end

            @session.on(:tool_start) do |payload|
              @status.update(
                tool_name: payload[:name],
                tool_index: payload[:index] || 0,
                tool_total: payload[:total] || 0
              )
            end

            @session.on(:tool_complete) do |_payload|
              @status.update(tool_name: nil)
            end
          end

          def render_frame
            @render_mutex.synchronize do
              @screen.detect_size
              input_lines = @input.render(@screen.width)
              inp_h = [input_lines.length, Screen::INPUT_MIN_HEIGHT].max
              out_h = @screen.output_height(inp_h)
              output_lines = @output.render(@screen.width, out_h)
              status_line = @status.render(@screen.width)

              @screen.render(output_lines, status_line, input_lines)

              # Position cursor in the input region
              input_row = @screen.input_start_row(inp_h)
              @screen.position_cursor(@input.cursor_col, input_row)
            end
          end

          def dispatch_key(key)
            case key
            when :ctrl_c
              if @streaming
                # TODO: cancel current LLM request
                @streaming = false
                @status.update(thinking: false, tool_name: nil)
                @output.add_info('(interrupted)')
              else
                @input.handle_key(:ctrl_c)
              end
            when :ctrl_d
              if @input.empty?
                @running = false
                return
              end
            when :ctrl_l
              @screen.clear
              return
            when :page_up
              @output.scroll_up(5)
              return
            when :page_down
              @output.scroll_down(5)
              return
            else
              result = @input.handle_key(key)
              case result
              when :pass
                handle_pass_key(key)
              when Array
                action, text = result
                handle_submit(text) if action == :submit
              end
            end
          end

          def handle_pass_key(key)
            case key
            when :page_up then @output.scroll_up(5)
            when :page_down then @output.scroll_down(5)
            when :ctrl_d
              @running = false if @input.empty?
            end
          end

          def handle_submit(text)
            # Show the user's message in the output pane
            @output.add_message(:user, text)

            # Check for slash commands
            if text.start_with?('/')
              if text.strip == '/quit' || text.strip == '/exit'
                @running = false
                return
              end

              if @slash_handler
                handled = @slash_handler.call(text)
                return if handled
              end
            end

            # Check for bang commands
            if text.start_with?('!')
              handle_bang_command(text[1..])
              return
            end

            # Send to LLM
            send_to_llm(text)
          end

          def send_to_llm(message)
            @output.begin_response
            buffer = String.new
            tool_index = 0

            @session.send_message(
              message,
              on_tool_call: lambda { |tc|
                tool_index += 1
                @output.add_tool_call(tc.name, tc.arguments.keys.join(', '))
                @session.emit(:tool_start, {
                  name: tc.name, args: tc.arguments,
                  index: tool_index, total: 0
                })
              },
              on_tool_result: lambda { |tr|
                result_preview = tr.to_s.lines.first(3).join.rstrip
                @output.add_tool_result(result_preview)
                @session.emit(:tool_complete, {
                  name: 'tool', result_preview: result_preview,
                  index: tool_index, total: 0
                })
              }
            ) do |chunk|
              if chunk.content
                buffer << chunk.content
                @output.append_chunk(buffer)
              end
            end

            # Finalize with rendered response
            rendered = render_markdown(buffer)
            @output.end_response(rendered)

            # Update stats
            update_stats
          rescue Chat::Session::BudgetExceeded => e
            @output.add_error("Budget exceeded: #{e.message}")
          rescue Interrupt
            @output.add_info('(interrupted)')
            @streaming = false
          rescue StandardError => e
            @output.add_error("LLM error: #{e.message}")
          end

          def handle_bang_command(cmd)
            @output.add_info("$ #{cmd}")
            output = `#{cmd} 2>&1`
            output.lines.each { |l| @output.add_info(l.chomp) }
            @output.add_info('')
          end

          def render_markdown(text)
            require 'legion/cli/chat/markdown_renderer'
            Chat::MarkdownRenderer.render(text)
          rescue LoadError
            text
          end

          def update_stats
            stats = @session.stats
            @status.update(
              tokens_in: stats[:input_tokens] || 0,
              tokens_out: stats[:output_tokens] || 0,
              cost: @session.estimated_cost,
              messages: stats[:messages_sent] || 0
            )
          end

          # --- Raw key reading (cannibalized from legion-tty App) ---

          def read_raw_key(io, timeout: nil)
            return nil unless io.wait_readable(timeout)

            ch = io.getc
            return nil unless ch

            if ch == "\e"
              read_escape_sequence(io, ch)
            else
              # Check for pasted text (multiple chars available immediately)
              buf = ch
              while io.ready?
                buf << io.getc
              end
              buf
            end
          rescue IOError, Errno::EIO
            nil
          end

          def read_escape_sequence(io, ch)
            return ch unless io.wait_readable(0.05) # 50ms to disambiguate bare Escape

            seq = ch + io.getc.to_s

            case seq[-1]
            when '['
              # CSI sequence
              while io.wait_readable(0.05)
                c = io.getc
                seq << c.to_s
                break if c && c.ord >= 0x40 && c.ord <= 0x7E
              end
            when 'O'
              # SS3 sequence
              if io.wait_readable(0.05)
                seq << io.getc.to_s
              end
            end

            seq
          end

          def normalize_key(raw)
            return KEY_MAP[raw] if KEY_MAP.key?(raw)

            # Single printable character
            return raw if raw.length == 1 && raw.ord >= 32

            # Multi-char paste (not an escape sequence)
            return raw if raw.length > 1 && !raw.start_with?("\e")

            # Unknown escape sequence — ignore
            nil
          end
        end
      end
    end
  end
end
