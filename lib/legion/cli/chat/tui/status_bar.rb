# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module TUI
        # Fixed single-row status bar rendered between the output pane and input region.
        # Shows model, thinking/tool status, cost, and notifications.
        class StatusBar
          PURPLE = "\e[38;2;127;119;221m"
          DIM = "\e[2m"
          BOLD = "\e[1m"
          YELLOW = "\e[33m"
          GREEN = "\e[32m"
          BG = "\e[48;2;40;40;50m"
          RESET = "\e[0m"

          SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

          def initialize
            @model = 'unknown'
            @thinking = false
            @tool_name = nil
            @tool_index = 0
            @tool_total = 0
            @tokens_in = 0
            @tokens_out = 0
            @cost = 0.0
            @messages = 0
            @permissions_mode = 'interactive'
            @notification = nil
            @notification_expires = nil
            @spinner_tick = 0
          end

          def update(**fields)
            fields.each do |key, value|
              case key
              when :model then @model = value
              when :thinking then @thinking = value; @tool_name = nil if value
              when :tool_name then @tool_name = value; @thinking = false if value
              when :tool_index then @tool_index = value
              when :tool_total then @tool_total = value
              when :tokens_in then @tokens_in = value
              when :tokens_out then @tokens_out = value
              when :cost then @cost = value
              when :messages then @messages = value
              when :permissions_mode then @permissions_mode = value
              end
            end
          end

          def notify(message, ttl: 5)
            @notification = message
            @notification_expires = Time.now + ttl
          end

          def tick
            @spinner_tick += 1
          end

          def render(width)
            segments = []

            # Activity indicator
            if @thinking
              spinner = SPINNER_FRAMES[@spinner_tick % SPINNER_FRAMES.length]
              segments << "#{PURPLE}#{spinner}#{RESET} thinking..."
            elsif @tool_name
              spinner = SPINNER_FRAMES[@spinner_tick % SPINNER_FRAMES.length]
              label = if @tool_total > 1
                        "[#{@tool_index}/#{@tool_total}] #{@tool_name}"
                      else
                        @tool_name
                      end
              segments << "#{PURPLE}#{spinner}#{RESET} #{label}"
            else
              segments << "#{GREEN}●#{RESET} ready"
            end

            # Model
            segments << "#{DIM}model:#{RESET} #{@model}"

            # Permissions
            segments << "#{DIM}perms:#{RESET} #{@permissions_mode}"

            # Tokens/cost
            if @tokens_in.positive? || @tokens_out.positive?
              segments << "#{DIM}tokens:#{RESET} #{format_tokens(@tokens_in)}/#{format_tokens(@tokens_out)}"
              segments << "#{DIM}cost:#{RESET} $#{format('%.4f', @cost)}" if @cost.positive?
            end

            # Notification (ephemeral)
            if @notification && @notification_expires
              if Time.now < @notification_expires
                segments << "#{YELLOW}#{@notification}#{RESET}"
              else
                @notification = nil
                @notification_expires = nil
              end
            end

            line = segments.join("  #{DIM}│#{RESET}  ")

            # Render as a full-width bar with background
            plain_len = strip_ansi(line).length
            padding = [width - plain_len, 0].max
            "#{BG}#{line}#{' ' * padding}#{RESET}"
          end

          private

          def format_tokens(n)
            if n >= 1_000_000
              "#{format('%.1f', n / 1_000_000.0)}M"
            elsif n >= 1_000
              "#{format('%.1f', n / 1_000.0)}K"
            else
              n.to_s
            end
          end

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '').gsub(/\e\].*?\e\\/, '')
          end
        end
      end
    end
  end
end
