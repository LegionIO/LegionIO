# frozen_string_literal: true

require 'tty-box'
require 'tty-markdown'
require 'tty-reader'
require 'tty-screen'
require 'tty-cursor'
require_relative 'palette'

module Legion
  module CLI
    module TTY
      module ChatUI
        SLASH_COMMANDS = {
          '/help'    => 'Show available commands',
          '/quit'    => 'Exit chat',
          '/clear'   => 'Clear conversation',
          '/status'  => 'Show system status',
          '/cost'    => 'Show session token usage',
          '/model'   => 'Switch model',
          '/compact' => 'Compact conversation history'
        }.freeze

        class << self
          def run
            p = Palette
            reader = ::TTY::Reader.new(interrupt: :exit, track_history: true)

            render_chat_header
            puts
            render_welcome
            puts

            token_count = 0
            turn = 0

            loop do
              prompt_text = "  #{p.fg(:cardinal)}\u276f#{p.reset} "
              input = reader.read_line(prompt_text)&.strip

              break if input.nil?
              next if input.empty?
              break if input == '/quit'

              result = handle_slash_command(input, turn, token_count)
              if result
                turn        = result[:turn]        if result.key?(:turn)
                token_count = result[:token_count] if result.key?(:token_count)
                next
              end

              turn += 1
              token_count += input.split.size * 3

              response     = simulate_response(input, turn)
              token_count += response.split.size * 4

              render_response(response)
              puts
            end

            puts
            puts "  #{p.muted('Session ended.')} #{p.disabled("#{turn} turns, ~#{token_count} tokens")}"
            puts
          end

          private

          def handle_slash_command(input, turn, token_count)
            cursor = ::TTY::Cursor
            case input
            when '/help'
              render_help
              {}
            when '/clear'
              print cursor.clear_screen + cursor.move_to(0, 0)
              render_chat_header
              puts
              render_system_message('Conversation cleared.')
              puts
              { turn: 0, token_count: 0 }
            when '/status'
              render_status(turn, token_count)
              {}
            when '/cost'
              render_cost(token_count)
              {}
            else
              if input.start_with?('/')
                render_system_message("Unknown command: #{input}. Type /help for available commands.")
                puts
                {}
              end
            end
          end

          def render_chat_header
            p = Palette
            width = [::TTY::Screen.width, 80].min

            puts "  #{p.border('─' * (width - 4))}"
            puts "  #{p.heading('Legion Chat')}  #{p.muted('(TTY Toolkit POC)')}"
            puts "  #{p.border('─' * (width - 4))}"
          end

          def render_welcome
            p = Palette
            puts "  #{p.body('Type a message to chat. Use')} #{p.accent('/help')} #{p.body('for commands.')}"
          end

          def render_help
            p = Palette
            puts
            puts "  #{p.heading('Commands')}"
            puts
            SLASH_COMMANDS.each do |cmd, desc|
              puts "  #{p.accent(cmd.ljust(12))} #{p.body(desc)}"
            end
            puts
          end

          def render_system_message(text)
            p = Palette
            puts "  #{p.muted("\u00b7")} #{p.body(text)}"
          end

          def render_status(turn, tokens)
            p = Palette
            puts

            w = 48
            lines = [
              "#{p.label('Turns')}       #{p.body(turn.to_s)}",
              "#{p.label('Tokens')}      #{p.body("~#{tokens}")}",
              "#{p.label('Model')}       #{p.body('claude-opus-4-6')}",
              "#{p.label('Provider')}    #{p.body('anthropic')}",
              "#{p.label('Session')}     #{p.success('active')}"
            ]

            puts "  #{p.border('┌')} #{p.heading('Status')} #{p.border('─' * (w - 12))}#{p.border('┐')}"
            puts "  #{p.border('│')}#{' ' * w}#{p.border('│')}"
            lines.each do |line|
              puts "  #{p.border('│')}  #{line}#{' ' * 4}#{p.border('│')}"
            end
            puts "  #{p.border('│')}#{' ' * w}#{p.border('│')}"
            puts "  #{p.border('└')}#{p.border('─' * w)}#{p.border('┘')}"
            puts
          end

          def render_cost(tokens)
            p = Palette
            cost_estimate = (tokens / 1000.0 * 0.015).round(4)
            puts
            puts "  #{p.label('Tokens')}  #{p.body("~#{tokens}")}  #{p.muted('|')}  #{p.label('Cost')}  #{p.body("~$#{cost_estimate}")}"
            puts
          end

          def render_response(text)
            puts

            # Render as markdown
            rendered = ::TTY::Markdown.parse(
              text,
              width: [::TTY::Screen.width - 6, 74].min,
              theme: {
                em:     :italic,
                header: %i[bold],
                hr:     :dim,
                link:   [:underline],
                list:   [],
                strong: [:bold],
                table:  [],
                quote:  [:italic]
              }
            )

            rendered.each_line do |line|
              puts "  #{line}"
            end
          end

          def simulate_response(_input, turn)
            responses = [
              "I can help with that. Here's what I found:\n\n" \
              'The LegionIO extension system uses **auto-discovery** via `Bundler.load.specs` ' \
              "to find all `lex-*` gems. Each extension defines:\n\n" \
              "- **Runners** — the actual functions that execute\n" \
              "- **Actors** — execution modes (subscription, polling, interval)\n" \
              "- **Helpers** — shared utilities for the extension\n\n" \
              "```ruby\nmodule Legion::Extensions::MyExtension\n  module Runners\n    module Process\n      " \
              "def handle(payload)\n        # Your logic here\n      end\n    end\n  end\nend\n```\n\n" \
              'Would you like me to scaffold a new extension?',

              "Looking at the current GAIA tick cycle, here's the phase breakdown:\n\n" \
              "| Phase | Name | Purpose |\n" \
              "|-------|------|---------|\n" \
              "| 1 | sensory_input | Gather raw input signals |\n" \
              "| 2 | perception | Pattern recognition |\n" \
              "| 3 | memory_retrieval | Query lex-memory traces |\n" \
              "| 4 | knowledge_retrieval | Query Apollo knowledge base |\n" \
              "| 5 | working_memory | Integrate context |\n\n" \
              "The tick cycle runs at **configurable intervals** via `legion-gaia` settings.\n\n" \
              '> Note: Apollo knowledge retrieval requires a running PostgreSQL instance with pgvector.',

              "Here's a quick summary of what changed:\n\n" \
              "### Modified Files\n\n" \
              "1. `lib/legion/cli/tty/splash.rb` — New splash screen with TTY toolkit\n" \
              "2. `lib/legion/cli/tty/chat_ui.rb` — Chat mode proof of concept\n" \
              "3. `lib/legion/cli/tty/palette.rb` — Pastel-based palette wrapper\n\n" \
              "All rendering uses the **17-shade single-hue** palette. No colors outside the system.\n\n" \
              "```bash\nbundle exec exe/legion-tty\n```"
            ]

            responses[(turn - 1) % responses.length]
          end
        end
      end
    end
  end
end
