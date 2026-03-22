# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class EditFile < RubyLLM::Tool
          description 'Edit a file using either string replacement (old_text → new_text) or ' \
                      'line-number replacement (start_line/end_line → new_text). ' \
                      'String mode requires an exact unique match. ' \
                      'Line mode replaces lines start_line..end_line (1-based, inclusive); ' \
                      'omit end_line to replace a single line.'
          param :path,       type: 'string',  desc: 'Path to the file to edit'
          param :new_text,   type: 'string',  desc: 'The replacement text'
          param :old_text,   type: 'string',  desc: 'The exact text to find and replace (string mode)'
          param :start_line, type: 'integer', desc: 'First line to replace, 1-based (line mode)'
          param :end_line,   type: 'integer', desc: 'Last line to replace, 1-based inclusive (line mode; defaults to start_line)'

          def execute(path:, new_text:, old_text: nil, start_line: nil, end_line: nil)
            expanded = File.expand_path(path)
            return "Error: file not found: #{path}" unless File.exist?(expanded)

            require 'legion/cli/chat/checkpoint'

            if start_line
              line_replace(expanded, new_text, start_line, end_line || start_line)
            else
              return 'Error: old_text is required when not using line-number mode' if old_text.nil?

              string_replace(expanded, old_text, new_text)
            end
          rescue StandardError => e
            Legion::Logging.warn("EditFile#execute failed for #{path}: #{e.message}") if defined?(Legion::Logging)
            "Error editing #{path}: #{e.message}"
          end

          private

          def string_replace(expanded, old_text, new_text)
            content = File.read(expanded, encoding: 'utf-8')
            occurrences = content.scan(old_text).length

            return "Error: old_text not found in #{expanded}" if occurrences.zero?
            return "Error: old_text matches #{occurrences} locations — must be unique (provide more context)" if occurrences > 1

            Checkpoint.save(expanded)
            File.write(expanded, content.sub(old_text, new_text), encoding: 'utf-8')
            "Replaced 1 occurrence in #{expanded}"
          end

          def line_replace(expanded, new_text, start_line, end_line)
            lines = File.readlines(expanded, encoding: 'utf-8')
            total = lines.length

            return "Error: start_line #{start_line} out of bounds (file has #{total} lines)" if start_line < 1 || start_line > total
            return "Error: end_line #{end_line} out of bounds (file has #{total} lines)" if end_line < 1 || end_line > total
            return "Error: end_line #{end_line} is before start_line #{start_line}" if end_line < start_line

            Checkpoint.save(expanded)
            replacement_lines = new_text.end_with?("\n") ? [new_text] : ["#{new_text}\n"]
            lines[(start_line - 1)..(end_line - 1)] = replacement_lines
            File.write(expanded, lines.join, encoding: 'utf-8')
            "Replaced lines #{start_line}–#{end_line} in #{expanded}"
          end
        end
      end
    end
  end
end
