# frozen_string_literal: true

require 'net/http'
require 'json'

module Legion
  module CLI
    class Chat
      module ApolloWriteback
        RESEARCH_TOOLS = %w[read_file search_files search_content run_command].freeze
        KNOWLEDGE_TOOL = 'query_knowledge'
        NO_RESULTS_MARKER = 'No knowledge entries found'
        MAX_CONTENT_LENGTH = 4000
        MIN_CONTENT_LENGTH = 50

        module_function

        def evaluate_turn(tool_calls:, user_query:, response_text:, model_id:)
          return nil unless response_text && response_text.length >= MIN_CONTENT_LENGTH

          knowledge_calls = tool_calls.select { |t| t[:name]&.include?(KNOWLEDGE_TOOL) }
          research_calls = tool_calls.select { |t| RESEARCH_TOOLS.any? { |r| t[:name]&.include?(r) } }

          knowledge_queried = knowledge_calls.any?
          knowledge_found = knowledge_calls.any? { |t| !t[:result]&.include?(NO_RESULTS_MARKER) }
          researched = research_calls.any?

          action = classify_turn(
            knowledge_queried: knowledge_queried,
            knowledge_found:   knowledge_found,
            researched:        researched
          )

          return nil if action == :skip

          {
            action:              action,
            content:             truncate(response_text),
            user_query:          user_query,
            model_id:            model_id,
            research_tools_used: research_calls.size,
            apollo_had_results:  knowledge_found
          }
        end

        def ingest!(evaluation)
          return unless evaluation

          tags = derive_tags(evaluation[:user_query])
          tags << 'auto-synthesis'

          body = {
            content:          evaluation[:content],
            content_type:     'observation',
            tags:             tags,
            source_agent:     evaluation[:model_id] || 'chat-llm',
            source_channel:   'chat_synthesis',
            knowledge_domain: tags.first
          }

          uri = URI("http://127.0.0.1:#{apollo_port}/api/apollo/ingest")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 2
          http.read_timeout = 5
          req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
          req.body = ::JSON.dump(body)
          response = http.request(req)
          parsed = ::JSON.parse(response.body, symbolize_names: true)

          entry_id = parsed.dig(:data, :entry_id) || parsed[:entry_id]
          Legion::Logging.info("[apollo-writeback] ingested synthesis entry_id=#{entry_id}") if defined?(Legion::Logging)
          entry_id
        rescue Errno::ECONNREFUSED
          nil
        rescue StandardError => e
          Legion::Logging.debug("[apollo-writeback] ingest failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def classify_turn(knowledge_queried:, knowledge_found:, researched:)
          return :skip unless researched

          if knowledge_found
            # Apollo had results AND LLM did additional research = augmented knowledge
            :augment
          else
            # Apollo had nothing (or wasn't queried) + LLM researched = fresh knowledge
            :fresh
          end
        end

        def truncate(text)
          return text if text.length <= MAX_CONTENT_LENGTH

          text[0...MAX_CONTENT_LENGTH]
        end

        def derive_tags(query)
          return [] unless query

          words = query.downcase.gsub(/[^a-z0-9\s_-]/, '').split
          stop = %w[how does what is the a an for to of in and or with use using from by on it do are was were]
          words.reject { |w| stop.include?(w) || w.length < 3 }
               .uniq
               .first(5)
        end

        def apollo_port
          return 4567 unless defined?(Legion::Settings)

          Legion::Settings[:api]&.dig(:port) || 4567
        rescue StandardError
          4567
        end
      end
    end
  end
end
