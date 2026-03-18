# frozen_string_literal: true

module Legion
  module CLI
    module TTY
      module Palette
        # LegionIO canonical palette: 17 shades, one hue, no exceptions.
        COLORS = {
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

        class << self
          def c(name, text)
            rgb = COLORS[name]
            return text.to_s unless rgb

            "#{fg(name)}#{text}#{RESET}"
          end

          def bold(name, text)
            rgb = COLORS[name]
            return text.to_s unless rgb

            "#{BOLD}#{fg(name)}#{text}#{RESET}"
          end

          def dim(name, text)
            rgb = COLORS[name]
            return text.to_s unless rgb

            "#{DIM}#{fg(name)}#{text}#{RESET}"
          end

          def fg(name)
            rgb = COLORS[name]
            return '' unless rgb

            "\e[38;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m"
          end

          def reset
            RESET
          end

          # Semantic shortcuts
          def title(text)     = bold(:self_point, text)
          def heading(text)   = bold(:near_white, text)
          def body(text)      = c(:inner_nodes, text)
          def label(text)     = c(:cardinal, text)
          def accent(text)    = c(:mid_nodes, text)
          def muted(text)     = c(:diagonal_nodes, text)
          def disabled(text)  = c(:skip, text)
          def border(text)    = c(:inner_tier, text)
          def success(text)   = c(:cardinal, text)
          def caution(text)   = c(:innermost, text)
          def critical(text)  = bold(:self_point, text)
        end
      end
    end
  end
end
