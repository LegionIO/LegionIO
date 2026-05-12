# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchFiles < Legion::Tools::Base
          tool_name 'legion.search_files'
          description 'Find files matching a glob pattern. Returns matching file paths.'
          input_schema({
                         type:       'object',
                         properties: {
                           pattern:   { type: 'string', description: 'Glob pattern (e.g., "**/*.rb", "src/**/*.ts")' },
                           directory: { type: 'string', description: 'Directory to search in (default: current dir)' }
                         },
                         required:   ['pattern']
                       })

          def self.call(pattern:, directory: nil)
            dir = File.expand_path(directory || Dir.pwd)
            return "Error: directory not found: #{dir}" unless Dir.exist?(dir)

            matches = Dir.glob(File.join(dir, pattern))
            return "No files matching #{pattern} in #{dir}" if matches.empty?

            relative = matches.map { |f| f.sub("#{dir}/", '') }
            "#{relative.length} files matching #{pattern}:\n#{relative.join("\n")}"
          rescue StandardError => e
            Legion::Logging.warn("SearchFiles#execute failed for pattern #{pattern}: #{e.message}") if defined?(Legion::Logging)
            "Error searching: #{e.message}"
          end
        end
      end
    end
  end
end
