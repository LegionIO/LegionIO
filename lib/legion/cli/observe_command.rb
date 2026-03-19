# frozen_string_literal: true

require 'thor'
require 'legion/mcp/observer'

module Legion
  module CLI
    class ObserveCommand < Thor
      namespace :observe

      desc 'stats', 'Show MCP tool usage statistics'
      def stats
        data = Legion::MCP::Observer.stats

        if options['json']
          puts ::JSON.pretty_generate(serialize_stats(data))
          return
        end

        puts 'MCP Tool Observation Stats'
        puts '=' * 40
        puts "Total Calls:  #{data[:total_calls]}"
        puts "Tools Used:   #{data[:tool_count]}"
        puts "Failure Rate: #{(data[:failure_rate] * 100).round(1)}%"
        puts "Since:        #{data[:since]&.strftime('%Y-%m-%d %H:%M:%S')}"
        puts

        return if data[:top_tools].empty?

        puts 'Top Tools:'
        puts '-' * 60
        puts 'Tool                            Calls  Avg(ms)  Fails'
        puts '-' * 60
        data[:top_tools].each do |tool|
          puts format('%-30<name>s %6<calls>d %8<avg>d %6<fails>d',
                      name: tool[:name], calls: tool[:call_count],
                      avg: tool[:avg_latency_ms], fails: tool[:failure_count])
        end
      end

      desc 'recent', 'Show recent MCP tool calls'
      method_option :limit, type: :numeric, default: 20, aliases: '-n'
      def recent
        calls = Legion::MCP::Observer.recent(options['limit'] || 20)

        if options['json']
          puts ::JSON.pretty_generate(calls.map { |c| serialize_call(c) })
          return
        end

        if calls.empty?
          puts 'No recent tool calls recorded.'
          return
        end

        puts 'Tool                           Duration  Status Time'
        puts '-' * 70
        calls.reverse_each do |call|
          status = call[:success] ? 'OK' : 'FAIL'
          time = call[:timestamp]&.strftime('%H:%M:%S')
          puts format('%-30<tool>s %6<dur>dms %7<st>s %<tm>s',
                      tool: call[:tool_name], dur: call[:duration_ms], st: status, tm: time)
        end
      end

      desc 'reset', 'Clear all observation data'
      def reset
        print 'Clear all observation data? (yes/no): '
        return unless $stdin.gets&.strip&.downcase == 'yes'

        Legion::MCP::Observer.reset!
        puts 'Observation data cleared.'
      end

      desc 'embeddings', 'Show MCP tool embedding index status'
      def embeddings
        require 'legion/mcp/embedding_index'
        data = {
          index_size: Legion::MCP::EmbeddingIndex.size,
          coverage:   Legion::MCP::EmbeddingIndex.coverage,
          populated:  Legion::MCP::EmbeddingIndex.populated?
        }

        if options['json']
          puts ::JSON.pretty_generate(data.transform_keys(&:to_s))
          return
        end

        puts 'MCP Embedding Index'
        puts '=' * 40
        puts "Index Size: #{data[:index_size]}"
        puts "Coverage:   #{(data[:coverage] * 100).round(1)}%"
        puts "Populated:  #{data[:populated]}"
      end

      private

      def serialize_stats(data)
        {
          total_calls:  data[:total_calls],
          tool_count:   data[:tool_count],
          failure_rate: data[:failure_rate],
          since:        data[:since]&.iso8601,
          top_tools:    data[:top_tools].map { |t| t.transform_keys(&:to_s) }
        }
      end

      def serialize_call(call)
        call.transform_keys(&:to_s).tap do |c|
          c['timestamp'] = c['timestamp']&.iso8601 if c['timestamp']
        end
      end
    end
  end
end
