# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Tools
        class WebSearch < Legion::Tools::Base
          tool_name 'legion.web_search'
          description 'Search the web for information. Returns titles, URLs, and snippets from search results, ' \
                      'plus the full content of the top result.'
          input_schema({
                         type:       'object',
                         properties: {
                           query:       { type: 'string', description: 'The search query' },
                           max_results: { type: 'integer', description: 'Maximum number of results (default 5)' }
                         },
                         required:   ['query']
                       })

          def self.call(query:, max_results: 5)
            require 'legion/cli/chat/web_search'
            results = Chat::WebSearch.search(query, max_results: max_results)

            output = results[:results].map do |r|
              "### #{r[:title]}\n#{r[:url]}\n#{r[:snippet]}"
            end.join("\n\n")

            output += "\n\n---\n\n## Top Result Content\n\n#{results[:fetched_content]}" if results[:fetched_content]

            output
          rescue Chat::WebSearch::SearchError => e
            Legion::Logging.warn("WebSearch#execute search error for query #{query}: #{e.message}") if defined?(Legion::Logging)
            "Search error: #{e.message}"
          rescue StandardError => e
            Legion::Logging.warn("WebSearch#execute failed for query #{query}: #{e.message}") if defined?(Legion::Logging)
            "Error: #{e.message}"
          end
        end
      end
    end
  end
end
