# frozen_string_literal: true

require 'ruby_llm'

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class SummarizeTraces < RubyLLM::Tool
          description 'Get aggregate statistics from the metering database: total records, token usage, cost, ' \
                      'latency, status breakdown, and top extensions/workers. Use natural language queries like ' \
                      '"failed tasks today" or "most expensive calls this week".'
          param :query, type: 'string', desc: 'Natural language query describing what to summarize'

          def execute(query:)
            require 'legion/trace_search'
            result = Legion::TraceSearch.summarize(query)
            return "Error: #{result[:error]}" if result[:error]

            format_summary(result)
          rescue LoadError
            'Trace search unavailable (legion-llm or legion-data not loaded).'
          rescue StandardError => e
            Legion::Logging.warn("SummarizeTraces#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error summarizing traces: #{e.message}"
          end

          private

          def format_summary(data)
            lines = ["Trace Summary (#{data[:total_records]} records):\n"]
            lines << "  Tokens: #{data[:total_tokens_in]} in / #{data[:total_tokens_out]} out"
            lines << "  Cost: $#{data[:total_cost]}"
            lines << "  Latency: avg #{data[:avg_latency_ms]}ms / max #{data[:max_latency_ms]}ms"

            lines << format_time_range(data[:time_range])
            lines << format_status_counts(data[:status_counts])
            lines << format_top('Top Extensions', data[:top_extensions], :name)
            lines << format_top('Top Workers', data[:top_workers], :id)

            lines.compact.join("\n")
          end

          def format_time_range(range)
            return nil unless range && (range[:from] || range[:to])

            "  Time range: #{range[:from] || '?'} to #{range[:to] || '?'}"
          end

          def format_status_counts(counts)
            return nil if counts.nil? || counts.empty?

            parts = counts.map { |status, count| "#{status}: #{count}" }
            "  Status: #{parts.join(', ')}"
          end

          def format_top(title, items, key)
            return nil if items.nil? || items.empty?

            parts = items.map { |item| "#{item[key]} (#{item[:count]})" }
            "  #{title}: #{parts.join(', ')}"
          end
        end
      end
    end
  end
end
