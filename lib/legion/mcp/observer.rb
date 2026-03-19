# frozen_string_literal: true

require 'concurrent-ruby'

module Legion
  module MCP
    module Observer
      RING_BUFFER_MAX   = 500
      INTENT_BUFFER_MAX = 200

      module_function

      def record(tool_name:, duration_ms:, success:, params_keys: [], error: nil)
        now = Time.now

        counters_mutex.synchronize do
          entry = counters[tool_name] || { call_count: 0, total_latency_ms: 0.0, failure_count: 0,
                                           last_used: nil, last_error: nil }
          counters[tool_name] = {
            call_count:       entry[:call_count] + 1,
            total_latency_ms: entry[:total_latency_ms] + duration_ms.to_f,
            failure_count:    entry[:failure_count] + (success ? 0 : 1),
            last_used:        now,
            last_error:       success ? entry[:last_error] : error
          }
        end

        buffer_mutex.synchronize do
          ring_buffer << {
            tool_name:   tool_name,
            duration_ms: duration_ms,
            success:     success,
            params_keys: params_keys,
            error:       error,
            recorded_at: now
          }
          ring_buffer.shift if ring_buffer.size > RING_BUFFER_MAX
        end
      end

      def record_intent(intent, matched_tool_name)
        intent_mutex.synchronize do
          intent_buffer << { intent: intent, matched_tool: matched_tool_name, recorded_at: Time.now }
          intent_buffer.shift if intent_buffer.size > INTENT_BUFFER_MAX
        end
      end

      def tool_stats(tool_name)
        entry = counters_mutex.synchronize { counters[tool_name] }
        return nil unless entry

        count = entry[:call_count]
        avg   = count.positive? ? (entry[:total_latency_ms] / count).round(2) : 0.0

        {
          name:           tool_name,
          call_count:     count,
          avg_latency_ms: avg,
          failure_count:  entry[:failure_count],
          last_used:      entry[:last_used],
          last_error:     entry[:last_error]
        }
      end

      def all_tool_stats
        names = counters_mutex.synchronize { counters.keys.dup }
        names.to_h { |name| [name, tool_stats(name)] }
      end

      def stats
        all_names = counters_mutex.synchronize { counters.keys.dup }
        total     = all_names.sum { |n| counters_mutex.synchronize { counters[n][:call_count] } }
        failures  = all_names.sum { |n| counters_mutex.synchronize { counters[n][:failure_count] } }
        rate      = total.positive? ? (failures.to_f / total).round(4) : 0.0

        top = all_names
              .map { |n| tool_stats(n) }
              .sort_by { |s| -s[:call_count] }
              .first(10)

        {
          total_calls:  total,
          tool_count:   all_names.size,
          failure_rate: rate,
          top_tools:    top,
          since:        started_at
        }
      end

      def recent(limit = 10)
        buffer_mutex.synchronize { ring_buffer.last(limit) }
      end

      def recent_intents(limit = 10)
        intent_mutex.synchronize { intent_buffer.last(limit) }
      end

      def reset!
        counters_mutex.synchronize { counters.clear }
        buffer_mutex.synchronize { ring_buffer.clear }
        intent_mutex.synchronize { intent_buffer.clear }
        @started_at = Time.now
      end

      # Internal state accessors
      def counters
        @counters ||= {}
      end

      def counters_mutex
        @counters_mutex ||= Mutex.new
      end

      def ring_buffer
        @ring_buffer ||= []
      end

      def buffer_mutex
        @buffer_mutex ||= Mutex.new
      end

      def intent_buffer
        @intent_buffer ||= []
      end

      def intent_mutex
        @intent_mutex ||= Mutex.new
      end

      def started_at
        @started_at ||= Time.now
      end
    end
  end
end
