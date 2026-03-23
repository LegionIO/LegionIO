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
        class Reflect < RubyLLM::Tool
          description 'Reflect on the current conversation to extract useful knowledge, patterns, or decisions ' \
                      'worth remembering. Analyzes the provided text and ingests key learnings into the Apollo ' \
                      'knowledge graph and project memory. Use after completing a task or when you notice ' \
                      'something worth preserving for future sessions.'
          param :text, type: 'string', desc: 'Text to reflect on (conversation excerpt, decision rationale, or lesson learned)'
          param :domain, type: 'string', desc: 'Knowledge domain (e.g., "architecture", "debugging", "patterns")',
                         required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          EXTRACTION_PROMPT = <<~PROMPT
            Extract discrete, reusable knowledge entries from the following text.
            Each entry should be a standalone fact, pattern, decision, or procedure
            that would be useful in future conversations.

            Rules:
            - One entry per line, prefixed with "- "
            - Be specific and actionable, not vague
            - Include context (file paths, module names, patterns)
            - Skip trivial observations
            - Maximum 5 entries

            Return ONLY the entries, no headers or commentary.
          PROMPT

          def execute(text:, domain: nil)
            entries = extract_entries(text)
            return 'No actionable knowledge found to reflect on.' if entries.empty?

            results = ingest_entries(entries, domain)
            format_results(entries, results)
          rescue StandardError => e
            Legion::Logging.warn("Reflect#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error during reflection: #{e.message}"
          end

          private

          def extract_entries(text)
            return [text] unless llm_available?

            response = Legion::LLM.chat_direct(
              message: "#{EXTRACTION_PROMPT}\n\nText:\n#{text}",
              model: nil, provider: nil
            )
            parse_entries(response.content)
          rescue StandardError
            [text]
          end

          def parse_entries(content)
            content.lines
                   .map(&:strip)
                   .select { |line| line.start_with?('- ') }
                   .map { |line| line.sub(/\A- /, '').strip }
                   .reject(&:empty?)
                   .first(5)
          end

          def ingest_entries(entries, domain)
            results = { apollo: 0, memory: 0 }
            entries.each do |entry|
              results[:apollo] += 1 if ingest_to_apollo(entry, domain)
              results[:memory] += 1 if save_to_memory(entry)
            end
            results
          end

          def ingest_to_apollo(content, domain)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}/api/apollo/ingest")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            req.body = ::JSON.dump({
                                     content:          content,
                                     content_type:     'observation',
                                     tags:             %w[reflection auto-learned],
                                     source_agent:     'chat',
                                     source_channel:   'reflection',
                                     knowledge_domain: domain
                                   })
            response = http.request(req)
            response.is_a?(Net::HTTPSuccess)
          rescue StandardError
            false
          end

          def save_to_memory(entry)
            require 'legion/cli/chat/memory_store'
            MemoryStore.add(entry, scope: :project)
            true
          rescue StandardError
            false
          end

          def format_results(entries, results)
            lines = ["Reflected on #{entries.size} knowledge entries:\n"]
            entries.each_with_index { |e, i| lines << "  #{i + 1}. #{e}" }
            lines << ''
            lines << "Saved: #{results[:apollo]} to Apollo, #{results[:memory]} to memory"
            lines.join("\n")
          end

          def llm_available?
            defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat_direct)
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
