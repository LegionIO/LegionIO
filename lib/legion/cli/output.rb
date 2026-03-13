# frozen_string_literal: true

require 'json'

module Legion
  module CLI
    module Output
      # Use Legion::JSON if available, fall back to stdlib
      def self.encode_json(data)
        if defined?(Legion::JSON) && Legion::JSON.respond_to?(:dump)
          Legion::JSON.dump(data)
        else
          JSON.pretty_generate(data)
        end
      end

      COLORS = {
        reset:   "\e[0m",
        bold:    "\e[1m",
        dim:     "\e[2m",
        red:     "\e[31m",
        green:   "\e[32m",
        yellow:  "\e[33m",
        blue:    "\e[34m",
        magenta: "\e[35m",
        cyan:    "\e[36m",
        white:   "\e[37m",
        gray:    "\e[90m"
      }.freeze

      STATUS_ICONS = {
        ok:        'green',
        ready:     'green',
        running:   'green',
        enabled:   'green',
        loaded:    'green',
        completed: 'green',
        warning:   'yellow',
        pending:   'yellow',
        disabled:  'yellow',
        error:     'red',
        failed:    'red',
        dead:      'red',
        unknown:   'gray'
      }.freeze

      class Formatter
        attr_reader :json_mode, :color_enabled

        def initialize(json: false, color: true)
          @json_mode = json
          @color_enabled = color && $stdout.tty? && !json
        end

        def colorize(text, color)
          return text.to_s unless @color_enabled

          "#{COLORS[color]}#{text}#{COLORS[:reset]}"
        end

        def bold(text)
          colorize(text, :bold)
        end

        def dim(text)
          colorize(text, :dim)
        end

        def status_color(status)
          key = status.to_s.downcase.tr('.', '_').to_sym
          color_name = STATUS_ICONS[key] || 'gray'
          color_name.to_sym
        end

        def status(text)
          colorize(text, status_color(text))
        end

        # Print a section header
        def header(text)
          if @json_mode
            # no-op in json mode, data speaks for itself
          else
            puts colorize(text, :bold)
          end
        end

        # Print a key-value detail block
        def detail(hash, indent: 0)
          if @json_mode
            puts Output.encode_json(hash)
            return
          end

          pad = ' ' * indent
          max_key = hash.keys.map { |k| k.to_s.length }.max || 0

          hash.each do |key, value|
            label = colorize("#{key.to_s.ljust(max_key)}:", :cyan)
            val = case value
                  when true  then colorize('yes', :green)
                  when false then colorize('no', :red)
                  when nil   then colorize('(none)', :gray)
                  else value.to_s
                  end
            puts "#{pad}  #{label} #{val}"
          end
        end

        # Print a formatted table
        def table(headers, rows, title: nil)
          if @json_mode
            json_rows = rows.map { |row| headers.zip(row).to_h }
            puts Output.encode_json(title ? { title: title, data: json_rows } : json_rows)
            return
          end

          return puts dim('  (no results)') if rows.empty?

          all_rows = [headers] + rows
          widths = headers.each_index.map do |i|
            all_rows.map { |r| strip_ansi(r[i].to_s).length }.max
          end

          # Header
          puts if title
          header_line = headers.each_with_index.map { |h, i| colorize(h.to_s.upcase.ljust(widths[i]), :bold) }.join('  ')
          puts "  #{header_line}"
          puts "  #{widths.map { |w| colorize('-' * w, :gray) }.join('  ')}"

          # Rows
          rows.each do |row|
            line = row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join('  ')
            puts "  #{line}"
          end
        end

        # Print a success message
        def success(message)
          if @json_mode
            puts Output.encode_json(success: true, message: message)
          else
            puts "  #{colorize('>>', :green)} #{message}"
          end
        end

        # Print a warning
        def warn(message)
          if @json_mode
            puts Output.encode_json(warning: true, message: message)
          else
            puts "  #{colorize('!!', :yellow)} #{message}"
          end
        end

        # Print an error
        def error(message)
          if @json_mode
            puts Output.encode_json(error: true, message: message)
          else
            warn "  #{colorize('!!', :red)} #{message}"
          end
        end

        # Print raw JSON (for structured output)
        def json(data)
          puts Output.encode_json(data)
        end

        # Print a blank line (no-op in json mode)
        def spacer
          puts unless @json_mode
        end

        private

        def strip_ansi(str)
          str.gsub(/\e\[[0-9;]*m/, '')
        end
      end
    end
  end
end
