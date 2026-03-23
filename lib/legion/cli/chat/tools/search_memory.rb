# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class SearchMemory < RubyLLM::Tool
          description 'Search persistent memory and the Apollo knowledge graph for previously saved information. ' \
                      'Returns matching memory entries (substring match) and related Apollo knowledge entries when available. ' \
                      'Use this to recall project conventions, user preferences, past decisions, or learned facts.'
          param :query, type: 'string', desc: 'Search text (case-insensitive substring match for memory, semantic for Apollo)'

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(query:)
            require 'legion/cli/chat/memory_store'
            sections = []

            memory_results = MemoryStore.search(query)
            unless memory_results.empty?
              lines = memory_results.map { |r| "- #{r[:text]}" }
              sections << "Memory matches (#{memory_results.size}):\n#{lines.join("\n")}"
            end

            apollo_results = search_apollo(query)
            if apollo_results&.any?
              lines = apollo_results.map { |r| "- [#{r[:type] || 'fact'}] #{r[:content]} (confidence: #{r[:confidence] || 'n/a'})" }
              sections << "Apollo knowledge (#{apollo_results.size}):\n#{lines.join("\n")}"
            end

            return 'No matching memories or knowledge found.' if sections.empty?

            sections.join("\n\n")
          rescue StandardError => e
            Legion::Logging.warn("SearchMemory#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error searching memory: #{e.message}"
          end

          private

          def search_apollo(query)
            require 'net/http'
            require 'json'

            uri = URI("http://#{DEFAULT_HOST}:#{api_port}/api/apollo/query")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            request.body = ::JSON.generate({ query: query, limit: 5 })
            response = http.request(request)
            data = ::JSON.parse(response.body, symbolize_names: true)
            data[:data] || data[:results] || []
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
