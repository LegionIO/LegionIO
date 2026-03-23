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
        class IngestKnowledge < RubyLLM::Tool
          description 'Save a fact, observation, or concept to the Apollo knowledge graph for long-term retention. ' \
                      'Use this when the user shares important information, when you discover a project convention, ' \
                      'or when a key decision is made that should be remembered across sessions.'
          param :content, type: 'string', desc: 'The knowledge to store (a clear, concise statement)'
          param :content_type, type: 'string',
                desc: 'Type: fact, observation, concept, procedure, decision (default: observation)', required: false
          param :tags, type: 'string', desc: 'Comma-separated tags for categorization (optional)', required: false
          param :knowledge_domain, type: 'string', desc: 'Domain category (optional)', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'
          VALID_TYPES = %w[fact observation concept procedure decision].freeze

          def execute(content:, content_type: nil, tags: nil, knowledge_domain: nil)
            content_type = sanitize_type(content_type)
            tag_list = parse_tags(tags)

            data = apollo_ingest(
              content:          content,
              content_type:     content_type,
              tags:             tag_list,
              knowledge_domain: knowledge_domain
            )

            return "Failed to ingest: #{data[:error]}" if data[:error]

            id = data[:id] || data[:entry_id]
            "Saved to Apollo knowledge graph (id: #{id}, type: #{content_type}, tags: #{tag_list.join(', ')})"
          rescue Errno::ECONNREFUSED
            'Apollo unavailable (daemon not running). Knowledge was not saved.'
          rescue StandardError => e
            Legion::Logging.warn("IngestKnowledge#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error saving to knowledge graph: #{e.message}"
          end

          private

          def sanitize_type(content_type)
            type = (content_type || 'observation').to_s.downcase
            VALID_TYPES.include?(type) ? type : 'observation'
          end

          def parse_tags(tags)
            return [] unless tags.is_a?(String) && !tags.empty?

            tags.split(',').map(&:strip).reject(&:empty?)
          end

          def apollo_ingest(content:, content_type:, tags:, knowledge_domain:)
            body = {
              content:        content,
              content_type:   content_type,
              tags:           tags,
              source_agent:   'chat',
              source_channel: 'chat_tool'
            }
            body[:knowledge_domain] = knowledge_domain if knowledge_domain

            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}/api/apollo/ingest")
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
        end
      end
    end
  end
end
