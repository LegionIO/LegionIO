# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchMemory < RubyLLM::Tool
          description 'Search persistent memory for previously saved information. ' \
                      'Use this to recall project conventions, user preferences, or past decisions.'
          param :query, type: 'string', desc: 'Search text (case-insensitive substring match)'

          def execute(query:)
            require 'legion/cli/chat/memory_store'
            results = MemoryStore.search(query)
            return 'No matching memories found.' if results.empty?

            results.map { |r| "- #{r[:text]}" }.join("\n")
          rescue StandardError => e
            Legion::Logging.warn("SearchMemory#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error searching memory: #{e.message}"
          end
        end
      end
    end
  end
end
