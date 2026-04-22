# frozen_string_literal: true

require 'legion/cli/output'

module Legion
  module CLI
    class Chat
      module TUI
        # Output formatter that routes all output to the TUI OutputPane
        # instead of $stdout. Implements the same interface as Output::Formatter
        # so existing slash command handlers work unchanged.
        class Formatter
          attr_reader :json_mode, :color_enabled

          def initialize(output_pane)
            @pane = output_pane
            @json_mode = false
            @color_enabled = true
          end

          def colorize(text, color)
            "#{Output::COLORS[color]}#{text}#{Output::COLORS[:reset]}"
          end

          def bold(text)
            "#{Output::COLORS[:bold]}#{Output::COLORS[:heading]}#{text}#{Output::COLORS[:reset]}"
          end

          def dim(text)
            "#{Output::COLORS[:gray]}#{text}#{Output::COLORS[:reset]}"
          end

          def status_color(status)
            key = status.to_s.downcase.tr('.', '_').to_sym
            color_name = Output::STATUS_ICONS[key] || 'disabled'
            color_name.to_sym
          end

          def status(text)
            colorize(text, status_color(text))
          end

          def banner(version: nil)
            # TUI shows version info in the status bar — skip the ASCII banner
          end

          def header(text)
            @pane.add_raw("#{Output::COLORS[:bold]}#{Output::COLORS[:heading]}#{text}#{Output::COLORS[:reset]}")
          end

          def detail(hash, indent: 0)
            pad = ' ' * indent
            max_key = hash.keys.map { |k| k.to_s.length }.max || 0

            hash.each do |key, value|
              label = colorize("#{key.to_s.ljust(max_key)}:", :label)
              val = case value
                    when true  then colorize('yes', :accent)
                    when false then colorize('no', :muted)
                    when nil   then colorize('(none)', :disabled)
                    else value.to_s
                    end
              @pane.add_raw("#{pad}  #{label} #{val}")
            end
          end

          def table(headers, rows, title: nil) # rubocop:disable Lint/UnusedMethodArgument
            if rows.empty?
              @pane.add_raw(dim('  (no results)'))
              return
            end

            all_rows = [headers] + rows
            widths = headers.each_index.map do |i|
              all_rows.map { |r| strip_ansi(r[i].to_s).length }.max
            end

            header_line = headers.each_with_index.map { |h, i| colorize(h.to_s.upcase.ljust(widths[i]), :heading) }.join('  ')
            @pane.add_raw("  #{header_line}")
            @pane.add_raw("  #{widths.map { |w| colorize("\u2500" * w, :border) }.join('  ')}")

            rows.each do |row|
              line = row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join('  ')
              @pane.add_raw("  #{line}")
            end
          end

          def success(message)
            @pane.add_raw("  #{colorize("\u00BB", :accent)} #{message}")
          end

          def warn(message)
            @pane.add_raw("  #{colorize("\u00BB", :caution)} #{message}")
          end

          def error(message)
            @pane.add_raw("  #{colorize("\u00BB", :critical)} #{colorize(message, :critical)}")
          end

          def info(message)
            @pane.add_raw(dim("  #{message}"))
          end

          def spacer
            @pane.add_raw('')
          end

          def json(data)
            @pane.add_raw(Output.encode_json(data))
          end

          private

          def strip_ansi(str)
            str.to_s.gsub(/\e\[[0-9;]*[A-Za-z]/, '')
          end
        end
      end
    end
  end
end
