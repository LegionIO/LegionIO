# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchContent < RubyLLM::Tool
          description 'Search file contents for a regex pattern. Returns matching lines with context.'
          param :pattern, type: 'string', desc: 'Regex pattern to search for'
          param :directory, type: 'string', desc: 'Directory to search in (default: current dir)', required: false
          param :glob, type: 'string', desc: 'File glob filter (e.g., "*.rb")', required: false

          def execute(pattern:, directory: nil, glob: nil) # rubocop:disable Metrics/CyclomaticComplexity
            dir = File.expand_path(directory || Dir.pwd)
            return "Error: directory not found: #{dir}" unless Dir.exist?(dir)

            file_pattern = File.join(dir, glob || '**/*')
            files = Dir.glob(file_pattern).select { |f| File.file?(f) }
            regex = Regexp.new(pattern)

            results = []
            files.each do |file|
              begin
                File.readlines(file, encoding: 'utf-8').each_with_index do |line, i|
                  if line.match?(regex)
                    relative = file.sub("#{dir}/", '')
                    results << "#{relative}:#{i + 1}: #{line.rstrip}"
                  end
                rescue ArgumentError => e
                  Legion::Logging.debug("SearchContent#execute encoding error in #{file}: #{e.message}") if defined?(Legion::Logging)
                  next
                end
              rescue StandardError => e
                Legion::Logging.debug("SearchContent#execute skipping #{file}: #{e.message}") if defined?(Legion::Logging)
                next
              end
              break if results.length >= 50
            end

            return "No matches for /#{pattern}/ in #{dir}" if results.empty?

            "#{results.length} matches:\n#{results.join("\n")}"
          rescue RegexpError => e
            Legion::Logging.warn("SearchContent#execute invalid regex #{pattern}: #{e.message}") if defined?(Legion::Logging)
            "Error: invalid regex: #{e.message}"
          rescue StandardError => e
            Legion::Logging.warn("SearchContent#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error searching: #{e.message}"
          end
        end
      end
    end
  end
end
