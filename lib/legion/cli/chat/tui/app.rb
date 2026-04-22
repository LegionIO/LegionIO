# frozen_string_literal: true

require 'io/console'
require 'io/wait'
require_relative 'screen'
require_relative 'output_pane'
require_relative 'status_bar'
require_relative 'input_bar'

module Legion
  module CLI
    class Chat
      module TUI
        class App
          attr_reader :output

          KEY_MAP = {
            "\r"    => :enter,
            "\n"    => :enter,
            "\x7F"  => :backspace,
            "\b"    => :backspace,
            "\e[A"  => :up,
            "\e[B"  => :down,
            "\e[C"  => :right,
            "\e[D"  => :left,
            "\e[H"  => :home,
            "\e[F"  => :end,
            "\e[1~" => :home,
            "\e[4~" => :end,
            "\e[5~" => :page_up,
            "\e[6~" => :page_down,
            "\e[3~" => :delete,
            "\eOA"  => :up,
            "\eOB"  => :down,
            "\eOC"  => :right,
            "\eOD"  => :left,
            "\eOH"  => :home,
            "\eOF"  => :end,
            "\x01"  => :ctrl_a,
            "\x02"  => :ctrl_b,
            "\x03"  => :ctrl_c,
            "\x04"  => :ctrl_d,
            "\x05"  => :ctrl_e,
            "\x0B"  => :ctrl_k,
            "\x0C"  => :ctrl_l,
            "\x15"  => :ctrl_u,
            "\x17"  => :ctrl_w,
            "\t"    => :tab
          }.freeze

          def initialize(session:, model_id: 'unknown', permissions_mode: 'interactive', # rubocop:disable Metrics/ParameterLists
                         slash_handler: nil, completions: [], banner: nil)
            @session = session
            @screen = Screen.new
            @output = OutputPane.new
            @status = StatusBar.new
            @input = InputBar.new(completions: completions)
            @slash_handler = slash_handler
            @running = false
            @streaming = false
            @dirty = true
            @llm_thread = nil

            # Self-pipe: write end wakes the select() in the main loop
            @wake_r, @wake_w = IO.pipe

            @status.update(model: model_id, permissions_mode: permissions_mode)
            setup_session_events

            return unless banner

            banner.to_s.lines.each { |l| @output.add_info(l.chomp) }
            @output.add_info('')
          end

          def run # rubocop:disable Metrics/CyclomaticComplexity
            @running = true
            @screen.clear
            @screen.hide_cursor

            prev_winch = Signal.trap('WINCH') do
              @screen.refresh_size
              wake!
            end

            $stdin.raw do |raw_in|
              render_frame
              @screen.show_cursor

              while @running
                render_frame if @dirty

                # IO.select: wait for stdin data OR wake-pipe signal
                # Short timeout during streaming (spinner), long when idle
                timeout = @streaming ? 0.08 : 5.0
                ready = IO.select([raw_in, @wake_r], nil, nil, timeout)

                # Drain the wake pipe if it fired
                @wake_r.read_nonblock(1024, exception: false) if ready && ready[0].include?(@wake_r)

                # Tick spinner during streaming regardless of input
                if @streaming
                  @status.tick
                  @dirty = true
                end

                # Read key if stdin is ready
                next unless ready && ready[0].include?(raw_in)

                raw_key = read_raw_key(raw_in)
                next unless raw_key

                key = normalize_key(raw_key)
                if key
                  @dirty = true
                  dispatch_key(key)
                end
              end
            end
          rescue Interrupt
            # Ctrl+C during raw mode
          ensure
            Signal.trap('WINCH', prev_winch || 'DEFAULT')
            @llm_thread&.join(2)
            begin
              @wake_r.close
            rescue StandardError
              nil
            end
            begin
              @wake_w.close
            rescue StandardError
              nil
            end
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

          # Wake the main event loop from a background thread.
          def wake!
            @wake_w.write_nonblock('.', exception: false)
          end

          def setup_session_events
            @session.on(:llm_start) do |_payload|
              @streaming = true
              @status.update(thinking: true)
              wake!
            end

            @session.on(:llm_first_token) do |_payload|
              @status.update(thinking: false)
              wake!
            end

            @session.on(:llm_complete) do |_payload|
              @streaming = false
              @status.update(thinking: false, tool_name: nil)
              wake!
            end

            @session.on(:tool_start) do |payload|
              @status.update(
                tool_name:  payload[:name],
                tool_index: payload[:index] || 0,
                tool_total: payload[:total] || 0
              )
              wake!
            end

            @session.on(:tool_complete) do |_payload|
              @status.update(tool_name: nil)
              wake!
            end
          end

          def render_frame
            input_lines = @input.render(@screen.width)
            inp_h = [input_lines.length, Screen::INPUT_MIN_HEIGHT].max
            out_h = @screen.output_height(inp_h)
            output_lines = @output.render(@screen.width, out_h)
            status_line = @status.render(@screen.width)

            @screen.render(output_lines, status_line, input_lines)

            input_row = @screen.input_start_row(inp_h)
            @screen.position_cursor(@input.cursor_col, input_row)
            @dirty = false
          end

          def dispatch_key(key)
            case key
            when :ctrl_c
              if @streaming
                @streaming = false
                @status.update(thinking: false, tool_name: nil)
                @output.add_info('(interrupted)')
              else
                @input.handle_key(:ctrl_c)
              end
            when :ctrl_d
              @running = false if @input.empty?
            when :ctrl_l
              @screen.clear
              @dirty = true
            when :page_up
              @output.scroll_up(5)
            when :page_down
              @output.scroll_down(5)
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
            @output.add_message(:user, text)

            if text.start_with?('/')
              if ['/quit', '/exit'].include?(text.strip)
                @running = false
                return
              end

              if @slash_handler
                handled = @slash_handler.call(text)
                return if handled
              end
            end

            if text.start_with?('!')
              handle_bang_command(text[1..])
              return
            end

            # LLM call runs in background thread so event loop stays alive
            send_to_llm_async(text)
          end

          def send_to_llm_async(message)
            @output.begin_response
            @llm_thread = Thread.new do
              buffer = String.new
              tool_index = 0

              @session.send_message(
                message,
                on_tool_call:   lambda { |tc|
                  tool_index += 1
                  @output.add_tool_call(tc.name, tc.arguments.keys.join(', '))
                  @session.emit(:tool_start, {
                                  name: tc.name, args: tc.arguments,
                    index: tool_index, total: 0
                                })
                  wake!
                },
                on_tool_result: lambda { |tr|
                  result_preview = tr.to_s.lines.first(3).join.rstrip
                  @output.add_tool_result(result_preview)
                  @session.emit(:tool_complete, {
                                  name: 'tool', result_preview: result_preview,
                    index: tool_index, total: 0
                                })
                  wake!
                }
              ) do |chunk|
                if chunk.content
                  buffer << chunk.content
                  @output.append_chunk(chunk.content)
                  @dirty = true
                  wake!
                end
              end

              rendered = render_markdown(buffer)
              @output.end_response(rendered)
              update_stats
              @dirty = true
              wake!
            rescue Chat::Session::BudgetExceeded => e
              @output.add_error("Budget exceeded: #{e.message}")
              wake!
            rescue StandardError => e
              @output.add_error("LLM error: #{e.message}")
              @streaming = false
              wake!
            end
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
              tokens_in:  stats[:input_tokens] || 0,
              tokens_out: stats[:output_tokens] || 0,
              cost:       @session.estimated_cost,
              messages:   stats[:messages_sent] || 0
            )
          end

          # --- Raw key reading ---

          def read_raw_key(io)
            ch = io.read_nonblock(1, exception: false)
            return nil if ch == :wait_readable || ch.nil?

            if ch == "\e"
              read_escape_sequence(io, ch)
            else
              buf = ch
              while (c = io.read_nonblock(1, exception: false)) && c != :wait_readable && c
                buf << c
              end
              buf
            end
          rescue IOError, Errno::EIO
            nil
          end

          def read_escape_sequence(io, char)
            # Brief wait for rest of escape sequence
            return char unless io.wait_readable(0.05)

            c2 = io.read_nonblock(1, exception: false)
            return char if c2 == :wait_readable || c2.nil?

            seq = char + c2

            case c2
            when '['
              # CSI: read until final byte (0x40-0x7E)
              loop do
                break unless io.wait_readable(0.05)

                c = io.read_nonblock(1, exception: false)
                break if c == :wait_readable || c.nil?

                seq << c
                break if c.ord.between?(0x40, 0x7E)
              end
            when 'O'
              # SS3: one more byte
              if io.wait_readable(0.05)
                c = io.read_nonblock(1, exception: false)
                seq << c if c && c != :wait_readable
              end
            end

            seq
          end

          def normalize_key(raw)
            return KEY_MAP[raw] if KEY_MAP.key?(raw)
            return raw if raw.length == 1 && raw.ord >= 32
            return raw if raw.length > 1 && !raw.start_with?("\e")

            nil
          end
        end
      end
    end
  end
end
