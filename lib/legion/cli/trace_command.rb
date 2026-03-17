# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class TraceCommand < Thor
      namespace 'trace'

      desc 'search QUERY', 'Search traces with natural language'
      option :limit, type: :numeric, default: 50
      def search(*query_parts)
        require 'legion/trace_search'
        query = query_parts.join(' ')
        say "Searching: #{query}", :yellow

        result = Legion::TraceSearch.search(query, limit: options[:limit])
        if result[:error]
          say "Error: #{result[:error]}", :red
          return
        end

        say "Found #{result[:count]} results", :green
        result[:results].first(20).each do |r|
          say "  #{r[:created_at]} #{r[:extension]}.#{r[:runner_function]} #{r[:status]} $#{r[:cost_usd] || 0}"
        end
      end

      default_task :search
    end
  end
end
