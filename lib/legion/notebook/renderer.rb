# frozen_string_literal: true

module Legion
  module Notebook
    module Renderer
      RESET  = "\e[0m"
      BOLD   = "\e[1m"
      DIM    = "\e[2m"
      YELLOW = "\e[33m"
      CYAN   = "\e[36m"
      GREEN  = "\e[32m"
      RED    = "\e[31m"
      RULE   = "\e[2m#{'─' * 60}\e[0m".freeze

      def self.render_notebook(notebook, color: true)
        lines = []
        kernel = notebook[:kernel]
        lines << (color ? "#{BOLD}#{CYAN}Kernel: #{kernel}#{RESET}" : "Kernel: #{kernel}") if kernel

        notebook[:cells].each_with_index do |cell, idx|
          lines << ''
          lines << render_cell_header(idx + 1, cell[:type], color)
          lines << render_cell_source(cell, notebook[:language], color)
          lines += render_cell_outputs(cell[:outputs], color) unless cell[:outputs].empty?
        end

        lines.join("\n")
      end

      def self.render_cell_header(index, type, color)
        label = "[#{type}] Cell #{index}"
        color ? "#{BOLD}#{YELLOW}#{label}#{RESET}" : label
      end

      def self.render_cell_source(cell, language, color)
        return '' if cell[:source].empty?

        if cell[:type] == 'code'
          highlight(cell[:source], language, color)
        else
          color ? "#{DIM}#{cell[:source]}#{RESET}" : cell[:source]
        end
      end

      def self.render_cell_outputs(outputs, color)
        outputs.filter_map do |output|
          next if output[:text].to_s.strip.empty?

          prefix = color ? "#{DIM}  => " : '  => '
          suffix = color ? RESET : ''
          "#{prefix}#{output[:text].strip}#{suffix}"
        end
      end

      def self.highlight(code, language, color)
        return code unless color

        begin
          require 'rouge'
          lexer     = Rouge::Lexer.find(language.to_s) || Rouge::Lexers::PlainText.new
          formatter = Rouge::Formatters::Terminal256.new(Rouge::Themes::Monokai.new)
          formatter.format(lexer.lex(code))
        rescue LoadError => e
          Legion::Logging.debug "Notebook::Renderer#highlight rouge not available: #{e.message}" if defined?(Legion::Logging)
          code
        end
      end

      def self.rule(color)
        color ? RULE : ('-' * 60)
      end
    end
  end
end
