# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class ReadFile < Legion::Tools::Base
          tool_name 'legion.read_file'
          description 'Read the contents of a file. Returns the file content with line numbers.'
          input_schema({
                         type:       'object',
                         properties: {
                           path:   { type: 'string', description: 'Absolute or relative path to the file' },
                           offset: { type: 'integer', description: 'Line number to start reading from (1-based)' },
                           limit:  { type: 'integer', description: 'Maximum number of lines to read' }
                         },
                         required:   ['path']
                       })

          def self.call(path:, offset: nil, limit: nil)
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
            Legion::Logging.warn("ReadFile#execute failed for #{path}: #{e.message}") if defined?(Legion::Logging)
            "Error reading #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
