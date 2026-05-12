# frozen_string_literal: true

require 'legion/cli/chat_command'
require 'fileutils'

module Legion
  module CLI
    class Chat
      module Tools
        class WriteFile < Legion::Tools::Base
          tool_name 'legion.write_file'
          description 'Create a new file or overwrite an existing file with the given content.'
          input_schema({
                         type:       'object',
                         properties: {
                           path:    { type: 'string', description: 'Path to the file to write' },
                           content: { type: 'string', description: 'Content to write to the file' }
                         },
                         required:   %w[path content]
                       })

          def self.call(path:, content:)
            expanded = File.expand_path(path)
            require 'legion/cli/chat/checkpoint'
            Checkpoint.save(expanded)
            FileUtils.mkdir_p(File.dirname(expanded))
            File.write(expanded, content, encoding: 'utf-8')
            "Wrote #{content.lines.count} lines to #{expanded}"
          rescue StandardError => e
            Legion::Logging.warn("WriteFile#execute failed for #{path}: #{e.message}") if defined?(Legion::Logging)
            "Error writing #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
