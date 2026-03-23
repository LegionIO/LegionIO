# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SaveMemory < RubyLLM::Tool
          description 'Save important information to persistent memory for future sessions. ' \
                      'Also ingests into the Apollo knowledge graph when available for semantic search. ' \
                      'Use this when you learn something important about the project, user preferences, ' \
                      'key decisions, or recurring patterns that should be remembered.'
          param :text, type: 'string', desc: 'The information to remember'
          param :scope, type: 'string', desc: 'Memory scope: "project" (default) or "global"', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(text:, scope: 'project')
            require 'legion/cli/chat/memory_store'
            sym_scope = scope.to_s == 'global' ? :global : :project
            path = MemoryStore.add(text, scope: sym_scope)
            apollo_status = ingest_to_apollo(text, sym_scope)

            parts = ["Saved to #{sym_scope} memory (#{path})"]
            parts << apollo_status if apollo_status
            parts.join("\n")
          rescue StandardError => e
            Legion::Logging.warn("SaveMemory#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error saving memory: #{e.message}"
          end

          private

          def ingest_to_apollo(text, scope)
            require 'net/http'
            require 'json'

            uri = URI("http://#{DEFAULT_HOST}:#{api_port}/api/apollo/ingest")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            request.body = ::JSON.generate({
                                             content: text,
                                             type:    'memory',
                                             source:  "chat:#{scope}",
                                             tags:    ['memory', scope.to_s]
                                           })
            response = http.request(request)
            data = ::JSON.parse(response.body, symbolize_names: true)
            return nil if data[:error]

            'Also ingested into Apollo knowledge graph.'
          rescue StandardError
            nil
          end

          def api_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end
        end
      end
    end
  end
end
