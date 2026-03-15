# frozen_string_literal: true

require 'json'
require 'legion/cli/theme'

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

      # Purple-only palette mapped to semantic names.
      # Legacy ANSI names (red, green, etc.) remap to purple intensity shades
      # so all existing code works but renders on-brand.
      COLORS = {
        reset:    "\e[0m",
        bold:     "\e[1m",
        dim:      "\e[2m",

        # Legacy names → purple intensity equivalents
        red:      Theme.c(:self_point),     # errors: brightest
        green:    Theme.c(:cardinal),       # success: calm/nominal
        yellow:   Theme.c(:innermost),      # warnings: medium-bright
        blue:     Theme.c(:mid_nodes),
        magenta:  Theme.c(:inner_nodes),
        cyan:     Theme.c(:mid_nodes),
        white:    Theme.c(:near_white),
        gray:     Theme.c(:mid_arcs),

        # Semantic theme names
        title:    Theme.c(:self_point),
        heading:  Theme.c(:near_white),
        body:     Theme.c(:inner_nodes),
        label:    Theme.c(:cardinal),
        accent:   Theme.c(:mid_nodes),
        muted:    Theme.c(:diagonal_nodes),
        disabled: Theme.c(:skip),
        border:   Theme.c(:inner_tier),
        node:     Theme.c(:cardinal),

        # Status intensity (no traffic lights)
        nominal:  Theme.c(:cardinal),
        caution:  Theme.c(:innermost),
        critical: Theme.c(:self_point)
      }.freeze

      # Status → intensity mapping. Brightness communicates urgency.
      STATUS_ICONS = {
        ok:        'nominal',
        ready:     'nominal',
        running:   'nominal',
        enabled:   'nominal',
        loaded:    'nominal',
        completed: 'nominal',
        warning:   'caution',
        pending:   'caution',
        disabled:  'muted',
        error:     'critical',
        failed:    'critical',
        dead:      'critical',
        unknown:   'disabled'
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
          return text.to_s unless @color_enabled

          "#{COLORS[:bold]}#{COLORS[:heading]}#{text}#{COLORS[:reset]}"
        end

        def dim(text)
          return text.to_s unless @color_enabled

          "#{COLORS[:gray]}#{text}#{COLORS[:reset]}"
        end

        def status_color(status)
          key = status.to_s.downcase.tr('.', '_').to_sym
          color_name = STATUS_ICONS[key] || 'disabled'
          color_name.to_sym
        end

        def status(text)
          colorize(text, status_color(text))
        end

        def banner(version: nil)
          puts Theme.render_banner(version: version, color: @color_enabled)
        end

        def header(text)
          return if @json_mode

          if @color_enabled
            puts "#{COLORS[:bold]}#{COLORS[:heading]}#{text}#{COLORS[:reset]}"
          else
            puts text
          end
        end

        def detail(hash, indent: 0)
          if @json_mode
            puts Output.encode_json(hash)
            return
          end

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
            puts "#{pad}  #{label} #{val}"
          end
        end

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

          puts if title
          header_line = headers.each_with_index.map { |h, i| colorize(h.to_s.upcase.ljust(widths[i]), :heading) }.join('  ')
          puts "  #{header_line}"
          puts "  #{widths.map { |w| colorize('─' * w, :border) }.join('  ')}"

          rows.each do |row|
            line = row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join('  ')
            puts "  #{line}"
          end
        end

        def success(message)
          if @json_mode
            puts Output.encode_json(success: true, message: message)
          else
            puts "  #{colorize('»', :accent)} #{message}"
          end
        end

        def warn(message)
          if @json_mode
            puts Output.encode_json(warning: true, message: message)
          else
            puts "  #{colorize('»', :caution)} #{message}"
          end
        end

        def error(message)
          if @json_mode
            puts Output.encode_json(error: true, message: message)
          else
            warn "  #{colorize('»', :critical)} #{colorize(message, :critical)}"
          end
        end

        def json(data)
          puts Output.encode_json(data)
        end

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
