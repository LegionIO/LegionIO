# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module MarkdownRenderer
        BOLD       = "\e[1m"
        DIM        = "\e[2m"
        ITALIC     = "\e[3m"
        RESET      = "\e[0m"
        CYAN       = "\e[36m"
        GREEN      = "\e[32m"
        YELLOW     = "\e[33m"
        CODE_BG    = "\e[48;5;236m\e[38;5;253m"
        RULE       = "\e[2m#{'─' * 40}\e[0m".freeze

        CODE_FENCE = /^```(\w*)\s*$/

        class << self
          def render(text, color: true)
            return text unless color

            lines = text.lines
            output = String.new
            i = 0

            while i < lines.length
              line = lines[i]

              if line.match?(CODE_FENCE)
                lang = line.match(CODE_FENCE)[1]
                code_lines = []
                i += 1
                while i < lines.length && !lines[i].match?(/^```\s*$/)
                  code_lines << lines[i]
                  i += 1
                end
                i += 1 # skip closing ```
                output << render_code_block(code_lines.join, lang)
              else
                output << render_line(line)
                i += 1
              end
            end

            output
          end

          private

          def render_code_block(code, lang)
            highlighted = highlight(code, lang)
            label = lang.empty? ? '' : "#{DIM}#{lang}#{RESET}\n"
            "#{label}#{highlighted}\n"
          end

          def highlight(code, lang)
            require 'rouge'

            lexer = Rouge::Lexer.find(lang) || Rouge::Lexers::PlainText.new
            formatter = Rouge::Formatters::Terminal256.new(Rouge::Themes::Monokai.new)
            formatter.format(lexer.lex(code))
          rescue LoadError
            code
          end

          def render_line(line)
            case line
            when /^\#{3,}\s+(.*)/
              "#{BOLD}#{CYAN}#{Regexp.last_match(1)}#{RESET}\n"
            when /^\#{2}\s+(.*)/
              "#{BOLD}#{GREEN}#{Regexp.last_match(1)}#{RESET}\n"
            when /^\#\s+(.*)/
              "#{BOLD}#{YELLOW}#{Regexp.last_match(1)}#{RESET}\n"
            when /^---\s*$/, /^\*\*\*\s*$/, /^___\s*$/
              "#{RULE}\n"
            when /^(\s*)[-*+]\s+(.*)/
              "#{Regexp.last_match(1)}  #{DIM}#{RESET} #{render_inline(Regexp.last_match(2))}\n"
            when /^(\s*)\d+\.\s+(.*)/
              "#{Regexp.last_match(1)}  #{render_inline(Regexp.last_match(2))}\n"
            when /^>\s*(.*)/
              "#{DIM}  #{render_inline(Regexp.last_match(1))}#{RESET}\n"
            else
              render_inline(line)
            end
          end

          def render_inline(text)
            result = text.dup
            result.gsub!(/\*\*(.+?)\*\*/, "#{BOLD}\\1#{RESET}")
            result.gsub!(/\*(.+?)\*/, "#{ITALIC}\\1#{RESET}")
            result.gsub!(/`([^`]+)`/, "#{CODE_BG}\\1#{RESET}")
            result
          end
        end
      end
    end
  end
end
