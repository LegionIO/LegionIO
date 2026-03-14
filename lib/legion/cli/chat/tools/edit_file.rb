# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class EditFile < RubyLLM::Tool
          description 'Replace a specific text string in a file. The old_text must match exactly.'
          param :path, type: 'string', desc: 'Path to the file to edit'
          param :old_text, type: 'string', desc: 'The exact text to find and replace'
          param :new_text, type: 'string', desc: 'The replacement text'

          def execute(path:, old_text:, new_text:)
            expanded = File.expand_path(path)
            return "Error: file not found: #{path}" unless File.exist?(expanded)

            content = File.read(expanded, encoding: 'utf-8')
            occurrences = content.scan(old_text).length

            return "Error: old_text not found in #{path}" if occurrences.zero?
            return "Error: old_text matches #{occurrences} locations — must be unique (provide more context)" if occurrences > 1

            updated = content.sub(old_text, new_text)
            File.write(expanded, updated, encoding: 'utf-8')
            "Replaced 1 occurrence in #{expanded}"
          rescue StandardError => e
            "Error editing #{path}: #{e.message}"
          end
        end
      end
    end
  end
end
