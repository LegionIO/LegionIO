# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SaveMemory < RubyLLM::Tool
          description 'Save important information to persistent memory for future sessions. ' \
                      'Use this when you learn something important about the project, user preferences, ' \
                      'key decisions, or recurring patterns that should be remembered.'
          param :text, type: 'string', desc: 'The information to remember'
          param :scope, type: 'string', desc: 'Memory scope: "project" (default) or "global"', required: false

          def execute(text:, scope: 'project')
            require 'legion/cli/chat/memory_store'
            sym_scope = scope.to_s == 'global' ? :global : :project
            path = MemoryStore.add(text, scope: sym_scope)
            "Saved to #{sym_scope} memory (#{path})"
          rescue StandardError => e
            "Error saving memory: #{e.message}"
          end
        end
      end
    end
  end
end
