# frozen_string_literal: true

require 'ruby_llm'

module Legion
  module CLI
    class Chat
      module Tools
        class ReadFile < RubyLLM::Tool
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

            "#{expanded} (#{lines.length} lines total)\n#{numbered.join}"
          rescue StandardError => e
            "Error reading #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
