# frozen_string_literal: true

require 'ruby_llm'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchContent < RubyLLM::Tool
          description 'Search file contents for a regex pattern. Returns matching lines with context.'
          param :pattern, type: 'string', desc: 'Regex pattern to search for'
          param :directory, type: 'string', desc: 'Directory to search in (default: current dir)', required: false
          param :glob, type: 'string', desc: 'File glob filter (e.g., "*.rb")', required: false

          def execute(pattern:, directory: nil, glob: nil)
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
                rescue ArgumentError
                  next
                end
              rescue StandardError
                next
              end
              break if results.length >= 50
            end

            return "No matches for /#{pattern}/ in #{dir}" if results.empty?

            "#{results.length} matches:\n#{results.join("\n")}"
          rescue RegexpError => e
            "Error: invalid regex: #{e.message}"
          rescue StandardError => e
            "Error searching: #{e.message}"
          end
        end
      end
    end
  end
end
