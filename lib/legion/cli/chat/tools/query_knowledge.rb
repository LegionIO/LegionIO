# frozen_string_literal: true

require 'ruby_llm'
require 'net/http'
require 'json'

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class QueryKnowledge < RubyLLM::Tool
          description 'Query the Apollo knowledge graph for facts, observations, concepts, and procedures. ' \
                      'Use this when the user asks about known facts, project knowledge, system behavior, ' \
                      'or anything that may have been ingested into the knowledge base.'
          param :query, type: 'string', desc: 'Natural language search query'
          param :domain, type: 'string', desc: 'Filter by knowledge domain (optional)', required: false
          param :limit, type: 'integer', desc: 'Max results (default: 10)', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(query:, domain: nil, limit: nil)
            limit = (limit || 10).clamp(1, 50)
            data = apollo_query(query: query, domain: domain, limit: limit)

            return "Apollo knowledge graph error: #{data[:error]}" if data[:error]

            entries = data[:entries] || []
            return 'No knowledge entries found matching that query.' if entries.empty?

            format_entries(entries)
          rescue StandardError => e
            Legion::Logging.warn("QueryKnowledge#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error querying knowledge graph: #{e.message}"
          end

          private

          def apollo_query(query:, domain:, limit:)
            body = { query: query, limit: limit }
            body[:domain] = domain if domain

            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}/api/apollo/query")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 10
            req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            req.body = ::JSON.dump(body)
            response = http.request(req)
            parsed = ::JSON.parse(response.body, symbolize_names: true)
            parsed[:data] || parsed
          end

          def apollo_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end

          def format_entries(entries)
            parts = entries.map.with_index(1) do |entry, idx|
              confidence = entry[:confidence] ? " (confidence: #{entry[:confidence]})" : ''
              tags = entry[:tags]&.any? ? " [#{entry[:tags].join(', ')}]" : ''
              "#{idx}. [#{entry[:content_type] || 'unknown'}]#{confidence} #{entry[:content]}#{tags}"
            end

            "Found #{entries.size} knowledge entries:\n\n#{parts.join("\n")}"
          end
        end
      end
    end
  end
end
