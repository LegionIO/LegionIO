# frozen_string_literal: true

require 'ruby_llm'
require 'fileutils'

module Legion
  module CLI
    class Chat
      module Tools
        class WriteFile < RubyLLM::Tool
          description 'Create a new file or overwrite an existing file with the given content.'
          param :path, type: 'string', desc: 'Path to the file to write'
          param :content, type: 'string', desc: 'Content to write to the file'

          def execute(path:, content:)
            expanded = File.expand_path(path)
            FileUtils.mkdir_p(File.dirname(expanded))
            File.write(expanded, content, encoding: 'utf-8')
            "Wrote #{content.lines.count} lines to #{expanded}"
          rescue StandardError => e
            "Error writing #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
