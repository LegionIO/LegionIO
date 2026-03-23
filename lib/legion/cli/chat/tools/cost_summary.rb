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
        class CostSummary < RubyLLM::Tool
          description 'Get cost and token usage summary from the running Legion daemon. Shows spending ' \
                      'for today, this week, and this month, plus top cost consumers by worker. ' \
                      'Use this to monitor LLM spending and identify expensive operations.'
          param :action, type:     'string',
                         desc:     'Action: "summary" (default), "top" (top consumers), or "worker" (specific worker)',
                         required: false
          param :worker_id, type: 'string', desc: 'Worker ID (required for "worker" action)', required: false
          param :limit, type: 'integer', desc: 'Number of top consumers to show (default: 5)', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(action: 'summary', worker_id: nil, limit: 5)
            case action.to_s
            when 'top'
              handle_top(limit.to_i.clamp(1, 20))
            when 'worker'
              return 'worker_id is required for the "worker" action.' if worker_id.nil? || worker_id.strip.empty?

              handle_worker(worker_id.strip)
            else
              handle_summary
            end
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach cost API).'
          rescue StandardError => e
            Legion::Logging.warn("CostSummary#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error fetching cost data: #{e.message}"
          end

          private

          def handle_summary
            data = api_get('/api/costs/summary?period=month')
            return "API error: #{data[:error]}" if data[:error]

            data = data[:data] || data
            lines = ["Cost Summary:\n"]
            lines << format('  Today:      $%.4f', (data[:today] || 0).to_f)
            lines << format('  This Week:  $%.4f', (data[:week] || 0).to_f)
            lines << format('  This Month: $%.4f', (data[:month] || 0).to_f)
            lines << "  Workers:    #{data[:workers] || 0}"
            lines.join("\n")
          end

          def handle_top(limit)
            data = api_get('/api/workers')
            return "API error: #{data[:error]}" if data[:error]

            workers = data[:data] || data
            workers = Array(workers).first(limit)
            return 'No workers found.' if workers.empty?

            lines = ["Top #{workers.size} Cost Consumers:\n"]
            workers.each_with_index do |w, i|
              id = w[:worker_id] || w[:id] || 'unknown'
              cost = fetch_worker_cost(id)
              lines << format('  %<rank>d. %-20<id>s $%<cost>.4f', rank: i + 1, id: id, cost: cost)
            end
            lines.join("\n")
          end

          def handle_worker(worker_id)
            data = api_get("/api/workers/#{worker_id}/value")
            return "API error: #{data[:error]}" if data[:error]

            data = data[:data] || data
            return "No cost data for worker #{worker_id}." if data.nil? || data.empty?

            lines = ["Worker: #{worker_id}\n"]
            data.each do |key, val|
              lines << "  #{key}: #{val}" unless key == :worker_id
            end
            lines.join("\n")
          end

          def fetch_worker_cost(worker_id)
            data = api_get("/api/workers/#{worker_id}/value")
            data = data[:data] || data
            (data[:total_cost_usd] || 0).to_f
          rescue StandardError
            0.0
          end

          def api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
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
