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
        class ViewTrends < RubyLLM::Tool
          description 'Show metric trends over time: cost, latency, volume, and failure rates bucketed into ' \
                      'time intervals. Use this to understand how system behavior changes over hours or days. ' \
                      'Ask "how are costs trending?" or "show me latency trends for the last 6 hours".'
          param :hours, type:     'integer',
                        desc:     'Time range in hours (default: 24, max: 168)',
                        required: false
          param :buckets, type:     'integer',
                          desc:     'Number of time buckets (default: 12, max: 48)',
                          required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(hours: 24, buckets: 12)
            hours = hours.to_i.clamp(1, 168)
            buckets = buckets.to_i.clamp(2, 48)

            data = api_get("/api/traces/trend?hours=#{hours}&buckets=#{buckets}")
            return "API error: #{data[:error][:message]}" if data[:error]

            format_trend(data[:data] || data)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach trend API).'
          rescue StandardError => e
            Legion::Logging.warn("ViewTrends#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error fetching trends: #{e.message}"
          end

          private

          def format_trend(data)
            trend_buckets = data[:buckets] || []
            return 'No trend data available.' if trend_buckets.empty?

            mins = data[:bucket_minutes] || 120
            lines = ["Trend (last #{data[:hours]}h, #{mins}min buckets):\n"]
            lines << '  Time                  Count   Avg Cost    Avg Lat  Fail%'
            lines << "  #{'—' * 56}"

            trend_buckets.each do |b|
              time = format_time(b[:time])
              count = b[:count] || 0
              cost = format('$%.4f', (b[:avg_cost] || 0).to_f)
              latency = format('%.0fms', (b[:avg_latency] || 0).to_f)
              fail_pct = format('%.1f%%', (b[:failure_rate] || 0).to_f * 100)
              lines << format('  %-20<time>s %6<count>d %10<cost>s %10<latency>s %6<fail>s',
                              time: time, count: count, cost: cost, latency: latency, fail: fail_pct)
            end

            lines << ''
            lines << summarize_direction(trend_buckets)
            lines.join("\n")
          end

          def format_time(iso_str)
            return iso_str unless iso_str.is_a?(String)

            Time.parse(iso_str).strftime('%m/%d %H:%M')
          rescue ArgumentError
            iso_str
          end

          def summarize_direction(trend_buckets)
            return '' if trend_buckets.size < 2

            first_half = trend_buckets[0...(trend_buckets.size / 2)]
            second_half = trend_buckets[(trend_buckets.size / 2)..]

            directions = []
            directions << direction_label('Volume', avg_metric(first_half, :count), avg_metric(second_half, :count))
            directions << direction_label('Cost', avg_metric(first_half, :avg_cost), avg_metric(second_half, :avg_cost))
            directions << direction_label('Latency', avg_metric(first_half, :avg_latency),
                                          avg_metric(second_half, :avg_latency))
            "  Direction: #{directions.join(' | ')}"
          end

          def avg_metric(buckets, key)
            values = buckets.map { |b| (b[key] || 0).to_f }
            return 0.0 if values.empty?

            values.sum / values.size
          end

          def direction_label(name, first_avg, second_avg)
            return "#{name}: stable" if first_avg.zero? && second_avg.zero?
            return "#{name}: rising" if first_avg.zero?

            change = ((second_avg - first_avg) / first_avg * 100).round(0)
            arrow = if change > 10
                      'rising'
                    elsif change < -10
                      'falling'
                    else
                      'stable'
                    end
            "#{name}: #{arrow} (#{'+' if change.positive?}#{change}%)"
          end

          def api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 10
            response = http.get(uri.request_uri)
            ::JSON.parse(response.body, symbolize_names: true)
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
