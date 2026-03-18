# frozen_string_literal: true

require 'tty-box'
require 'tty-progressbar'
require 'tty-screen'
require 'tty-font'
require 'tty-cursor'
require_relative 'palette'

module Legion
  module CLI
    module TTY
      module Splash
        BOOT_PHASES = [
          { name: 'settings',   label: 'legion-settings',  version: '1.3.2',  delay: 0.15 },
          { name: 'crypt',      label: 'legion-crypt',     version: '1.4.3',  delay: 0.20 },
          { name: 'transport',  label: 'legion-transport', version: '1.2.1', delay: 0.30 },
          { name: 'cache',      label: 'legion-cache',     version: '1.3.0',  delay: 0.15 },
          { name: 'data',       label: 'legion-data',      version: '1.4.2',  delay: 0.20 },
          { name: 'llm',        label: 'legion-llm',       version: '0.3.3',  delay: 0.15 },
          { name: 'gaia',       label: 'legion-gaia',      version: '0.8.0',  delay: 0.10 }
        ].freeze

        EXTENSIONS = %w[
          lex-node lex-health lex-tasker lex-scheduler lex-telemetry
          lex-memory lex-coldstart lex-apollo lex-dream lex-reflection
          lex-perception lex-attention lex-emotion lex-motivation
        ].freeze

        class << self
          def run(version: '0.0.0')
            cursor = ::TTY::Cursor
            print cursor.hide

            render_banner(version)
            puts
            boot_core_libraries
            puts
            load_extensions
            puts
            render_ready_line(version)
            puts

            print cursor.show
          end

          private

          def render_banner(version)
            p = Palette
            width = [::TTY::Screen.width, 60].min

            font = ::TTY::Font.new(:standard)
            ascii_lines = font.write('LEGION').split("\n")

            # Gradient the ASCII art across palette shades
            gradient = %i[inner_tier cardinal mid_nodes inner_nodes innermost near_white]

            puts
            ascii_lines.each_with_index do |line, i|
              shade = gradient[i % gradient.size]
              puts "  #{p.c(shade, line)}"
            end

            puts "  #{p.border('─' * (width - 4))}"
            puts "  #{p.accent('Async Job Engine & Cognitive Mesh')}  #{p.muted("v#{version}")}"
            puts "  #{p.border('─' * (width - 4))}"
          end

          def boot_core_libraries
            p = Palette
            puts "  #{p.heading('Core Libraries')}"
            puts

            BOOT_PHASES.each do |phase|
              puts "  #{p.success('✔')} #{p.label(phase[:label].ljust(20))} #{p.muted(phase[:version])}  #{p.success('ready')}"
            end
          end

          def load_extensions
            p = Palette
            puts "  #{p.heading('Extensions')}  #{p.muted("(#{EXTENSIONS.size} discovered)")}"
            puts

            bar = ::TTY::ProgressBar.new(
              "  #{p.fg(:cardinal)}:bar#{p.reset} :current/:total  #{p.fg(:diagonal_nodes)}:eta#{p.reset}",
              total:      EXTENSIONS.size,
              width:      30,
              complete:   "\u2588",
              incomplete: "\u2591",
              head:       "\u2588",
              output:     $stdout
            )

            EXTENSIONS.each { |_ext| bar.advance(1) }

            puts
            EXTENSIONS.each_slice(4) do |group|
              line = group.map { |ext| p.muted(ext.ljust(18)) }.join
              puts "  #{line}"
            end
          end

          def render_ready_line(version)
            p = Palette
            width = [::TTY::Screen.width, 60].min

            puts "  #{p.border('─' * (width - 4))}"

            content = "#{p.success('Ready')} #{p.body("#{EXTENSIONS.size} extensions")} " \
                      "#{p.muted('|')} #{p.body("#{BOOT_PHASES.size} libraries")} " \
                      "#{p.muted('|')} #{p.accent("v#{version}")}"
            puts "  #{p.border('┌')}#{p.border('─' * (width - 6))}#{p.border('┐')}"
            puts "  #{p.border('│')}  #{content}  #{p.border('│')}"
            puts "  #{p.border('└')}#{p.border('─' * (width - 6))}#{p.border('┘')}"
          end
        end
      end
    end
  end
end
