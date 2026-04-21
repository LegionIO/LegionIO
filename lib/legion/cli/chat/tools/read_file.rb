# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class ReadFile < RubyLLM::Tool
          MAX_OUTPUT_CHARS = 48_000

          description 'Read the contents of a file. Returns the file content with line numbers.'
          param :path, type: 'string', desc: 'Absolute or relative path to the file'
          param :offset, type: 'integer', desc: 'Line number to start reading from (1-based)', required: false
          param :limit, type: 'integer', desc: 'Maximum number of lines to read', required: false

          def execute(path:, offset: nil, limit: nil)
            expanded = File.expand_path(path)
            return "Error: file not found: #{path}" unless File.exist?(expanded)
            return "Error: path is a directory: #{path}" if File.directory?(expanded)

            lines = File.readlines(expanded, encoding: 'utf-8')
            start_line = [(offset || 1) - 1, 0].max
            count = limit || lines.length
            selected = lines[start_line, count] || []

            numbered = selected.each_with_index.map do |line, i|
              "#{(start_line + i + 1).to_s.rjust(5)} | #{line}"
            end

            result = "#{expanded} (#{lines.length} lines total)\n#{numbered.join}"
            max_chars = max_output_chars
            return result if result.length <= max_chars

            "#{result[0, max_chars]}\n\n[... truncated at #{max_chars} characters — use offset/limit params to read specific sections]"
          rescue StandardError => e
            Legion::Logging.warn("ReadFile#execute failed for #{path}: #{e.message}") if defined?(Legion::Logging)
            "Error reading #{path}: #{e.message}"
          end

          private

          # Returns the max output chars from settings with fallback to constant.
          # Memory usage note: Still reads entire file before truncation - this is intentional
          # to avoid complex streaming logic. For very large files, use offset/limit params.
          def max_output_chars
            Legion::Settings.dig(:chat, :tools, :max_output_chars) || MAX_OUTPUT_CHARS
          rescue StandardError
            MAX_OUTPUT_CHARS
          end
        end
      end
    end
  end
end
