# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchFiles < RubyLLM::Tool
          description 'Find files matching a glob pattern. Returns matching file paths.'
          param :pattern, type: 'string', desc: 'Glob pattern (e.g., "**/*.rb", "src/**/*.ts")'
          param :directory, type: 'string', desc: 'Directory to search in (default: current dir)', required: false

          def execute(pattern:, directory: nil)
            dir = File.expand_path(directory || Dir.pwd)
            return "Error: directory not found: #{dir}" unless Dir.exist?(dir)

            matches = Dir.glob(File.join(dir, pattern)).sort
            return "No files matching #{pattern} in #{dir}" if matches.empty?

            relative = matches.map { |f| f.sub("#{dir}/", '') }
            "#{relative.length} files matching #{pattern}:\n#{relative.join("\n")}"
          rescue StandardError => e
            "Error searching: #{e.message}"
          end
        end
      end
    end
  end
end
