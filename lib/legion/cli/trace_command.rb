# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class TraceCommand < Thor
      namespace 'trace'

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'search QUERY', 'Search traces with natural language'
      option :limit, type: :numeric, default: 50, desc: 'Max results to return'
      def search(*query_parts)
        require 'legion/trace_search'
        query = query_parts.join(' ')
        out = formatter

        out.header('Trace Search')
        puts "  Query: #{query}"
        out.spacer

        result = Legion::TraceSearch.search(query, limit: options[:limit])
        if result[:error]
          out.error("Search failed: #{result[:error]}")
          return
        end

        if options[:json]
          out.json(result)
          return
        end

        display_results(out, result)
      end

      default_task :search

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        private

        def display_results(out, result)
          total = result[:total] || result[:count] || 0
          shown = result[:results]&.size || 0
          truncated = result[:truncated] ? ' (truncated)' : ''

          out.success("#{shown} of #{total} results#{truncated}")

          if result[:filter]
            puts "  Filter: #{result[:filter].inspect}"
            out.spacer
          end

          return puts('  No results found.') if result[:results].nil? || result[:results].empty?

          result[:results].each_with_index do |row, idx|
            display_row(out, row, idx)
          end
        end

        def display_row(out, row, idx)
          ts = row[:created_at]&.strftime('%Y-%m-%d %H:%M:%S') || '?'
          ext = row[:extension] || '?'
          func = row[:runner_function] || '?'
          status = row[:status] || '?'
          cost = format('$%.4f', row[:cost_usd] || 0)
          tokens = "#{row[:tokens_in] || 0}in/#{row[:tokens_out] || 0}out"
          wall = row[:wall_clock_ms] ? "#{row[:wall_clock_ms]}ms" : nil

          line = "  #{idx + 1}. [#{ts}] #{ext}.#{func}"
          puts line
          detail = "     status: #{status} | cost: #{cost} | tokens: #{tokens}"
          detail += " | #{wall}" if wall
          detail += " | worker: #{row[:worker_id]}" if row[:worker_id]
          puts out.colorize(detail, status == 'success' ? :success : :warn)
        end
      end
    end
  end
end
