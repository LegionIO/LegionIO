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
        class KnowledgeStats < RubyLLM::Tool
          description 'Get statistics about the Apollo knowledge graph including total entries, ' \
                      'breakdowns by status and content type, recent activity, and average confidence. ' \
                      'Use this to understand the current state of the knowledge base.'

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute
            data = fetch_stats
            return "Apollo error: #{data[:error]}" if data[:error]

            format_stats(data)
          rescue Errno::ECONNREFUSED
            'Apollo unavailable (daemon not running).'
          rescue StandardError => e
            Legion::Logging.warn("KnowledgeStats#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error fetching knowledge stats: #{e.message}"
          end

          private

          def fetch_stats
            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}/api/apollo/stats")
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

          def format_stats(data)
            lines = ["Apollo Knowledge Graph Statistics:\n"]
            lines << "  Total entries: #{data[:total_entries] || 0}"
            lines << "  Recent (24h): #{data[:recent_24h] || 0}"
            lines << "  Avg confidence: #{data[:avg_confidence] || 0.0}"

            lines << format_breakdown('By Status', data[:by_status])
            lines << format_breakdown('By Content Type', data[:by_content_type])

            lines.compact.join("\n")
          end

          def format_breakdown(title, hash)
            return nil if hash.nil? || hash.empty?

            parts = hash.map { |key, count| "    #{key}: #{count}" }
            "\n  #{title}:\n#{parts.join("\n")}"
          end
        end
      end
    end
  end
end
