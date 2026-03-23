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
        class RelateKnowledge < RubyLLM::Tool
          description 'Find related knowledge entries in the Apollo knowledge graph. ' \
                      'Use this to discover connections between concepts, find supporting or contradicting facts, ' \
                      'or explore the knowledge neighborhood of a specific entry.'
          param :entry_id, type: 'integer', desc: 'The ID of the knowledge entry to find relations for'
          param :relation_types, type: 'string',
                desc: 'Comma-separated relation types to filter (supports, contradicts, related, derived_from)', required: false
          param :depth, type: 'integer', desc: 'Depth of relation traversal (1-3, default: 2)', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(entry_id:, relation_types: nil, depth: nil)
            depth = (depth || 2).clamp(1, 3)
            params = { depth: depth }
            params[:relation_types] = relation_types if relation_types

            data = apollo_related(entry_id, params)
            return "Apollo error: #{data[:error]}" if data[:error]

            entries = data[:entries] || []
            return "No related entries found for entry ##{entry_id}." if entries.empty?

            format_related(entry_id, entries, depth)
          rescue Errno::ECONNREFUSED
            'Apollo unavailable (daemon not running).'
          rescue StandardError => e
            Legion::Logging.warn("RelateKnowledge#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error finding related entries: #{e.message}"
          end

          private

          def apollo_related(entry_id, params)
            query_string = params.map { |k, v| "#{k}=#{v}" }.join('&')
            path = "/api/apollo/entries/#{entry_id}/related"
            path += "?#{query_string}" unless query_string.empty?

            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 10
            response = http.get(uri.request_uri)
            parsed = ::JSON.parse(response.body, symbolize_names: true)
            parsed[:data] || parsed
          end

          def apollo_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end

          def format_related(entry_id, entries, depth)
            header = "Related entries for ##{entry_id} (depth: #{depth}, found: #{entries.size}):\n\n"
            parts = entries.map.with_index(1) do |entry, idx|
              relation = entry[:relation_type] ? " [#{entry[:relation_type]}]" : ''
              confidence = entry[:confidence] ? " (conf: #{entry[:confidence]})" : ''
              "#{idx}.#{relation}#{confidence} #{entry[:content]}"
            end
            header + parts.join("\n")
          end
        end
      end
    end
  end
end
