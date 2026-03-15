# frozen_string_literal: true

module Legion
  module CLI
    module Theme
      # LegionIO canonical palette: 17 shades, one hue, no exceptions.
      # Sourced from legion_colors.html — the official color system.
      PALETTE = {
        void:           [7,   6,   15],
        background:     [14,  13,  26],
        deep:           [18,  16,  41],
        core_shell:     [24,  22,  58],
        glow_center:    [26,  22,  64],
        guide_rings:    [30,  28,  58],
        core_mid:       [33,  30,  80],
        skip:           [42,  39,  96],
        inner_tier:     [49,  46,  128],
        mid_arcs:       [61,  56,  138],
        diagonal_nodes: [74,  68,  168],
        cardinal:       [95,  87,  196],
        mid_nodes:      [127, 119, 221],
        inner_nodes:    [139, 131, 230],
        innermost:      [160, 154, 232],
        near_white:     [184, 178, 239],
        self_point:     [197, 194, 245]
      }.freeze

      RESET = "\e[0m"
      BOLD  = "\e[1m"
      DIM   = "\e[2m"

      def self.fg(red, green, blue)
        "\e[38;2;#{red};#{green};#{blue}m"
      end

      def self.c(name)
        rgb = PALETTE[name]
        return '' unless rgb

        fg(*rgb)
      end

      # ── Banner ──────────────────────────────────────────

      B = "\u2588"
      LOGO = [
        "#{B}      #{B * 5}  #{B * 5}  #{B * 2}  #{B * 5}  #{B}   #{B}",
        "#{B}      #{B}      #{B}      #{B * 2}  #{B}   #{B}  #{B * 2}  #{B}",
        "#{B}      #{B * 4}   #{B} #{B * 3}  #{B * 2}  #{B}   #{B}  #{B} #{B} #{B}",
        "#{B}      #{B}      #{B}   #{B}  #{B * 2}  #{B}   #{B}  #{B}  #{B * 2}",
        "#{B * 5}  #{B * 5}  #{B * 5}  #{B * 2}  #{B * 5}  #{B}   #{B}"
      ].freeze

      LOGO_GRADIENT = %i[cardinal mid_nodes self_point mid_nodes cardinal].freeze

      PAD = '      '

      def self.render_banner(version: nil, color: true)
        return plain_banner(version: version) unless color

        lines = []
        lines << "#{PAD}#{c(:mid_arcs)}\u00b7 #{c(:inner_tier)}#{'─' * 43} #{c(:mid_arcs)}\u00b7#{RESET}"
        lines << "#{PAD}#{c(:inner_tier)}╭#{'─' * 45}╮#{RESET}"
        lines << "#{PAD}#{c(:inner_tier)}│#{c(:cardinal)}  \u00b7#{' ' * 39}\u00b7  #{c(:inner_tier)}│#{RESET}"

        LOGO.each_with_index do |row, i|
          lc = c(LOGO_GRADIENT[i])
          lines << "#{PAD}#{c(:inner_tier)}│#{lc}    #{row}    #{c(:inner_tier)}│#{RESET}"
        end

        lines << "#{PAD}#{c(:inner_tier)}│#{c(:cardinal)}  \u00b7#{' ' * 39}\u00b7  #{c(:inner_tier)}│#{RESET}"
        lines << "#{PAD}#{c(:inner_tier)}╰#{'─' * 45}╯#{RESET}"
        lines << "#{PAD}#{c(:mid_arcs)}\u00b7 #{c(:inner_tier)}#{'─' * 43} #{c(:mid_arcs)}\u00b7#{RESET}"

        if version
          lines << ''
          lines << "#{PAD}  #{c(:mid_nodes)}Async Job Engine & Extension Ecosystem#{RESET}"
          lines << "#{PAD}  #{c(:diagonal_nodes)}v#{version}#{RESET}"
        end

        lines.join("\n")
      end

      def self.plain_banner(version: nil)
        lines = []
        lines << "#{PAD}\u00b7 #{'─' * 43} \u00b7"
        lines << "#{PAD}╭#{'─' * 45}╮"
        lines << "#{PAD}│  \u00b7#{' ' * 39}\u00b7  │"
        LOGO.each { |row| lines << "#{PAD}│    #{row}    │" }
        lines << "#{PAD}│  \u00b7#{' ' * 39}\u00b7  │"
        lines << "#{PAD}╰#{'─' * 45}╯"
        lines << "#{PAD}\u00b7 #{'─' * 43} \u00b7"
        if version
          lines << ''
          lines << "#{PAD}  Async Job Engine & Extension Ecosystem"
          lines << "#{PAD}  v#{version}"
        end
        lines.join("\n")
      end

      # ── Decorative helpers ──────────────────────────────

      def self.divider(width = 50, color_enabled: true)
        return "\u2500" * width unless color_enabled

        "#{c(:inner_tier)}#{"\u2500" * width}#{RESET}"
      end

      def self.orbital_header(text, color_enabled: true)
        return "── #{text} ──" unless color_enabled

        "#{c(:inner_tier)}── #{BOLD}#{c(:near_white)}#{text}#{RESET} #{c(:inner_tier)}──#{RESET}"
      end
    end
  end
end
