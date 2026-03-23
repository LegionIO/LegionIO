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
        class WorkerStatus < RubyLLM::Tool
          description 'View digital worker status on the running Legion daemon. List all workers, ' \
                      'show details for a specific worker, or check worker health. Digital workers ' \
                      'are AI-as-labor entities with lifecycle states, risk tiers, and cost tracking.'
          param :action, type:     'string',
                         desc:     'Action: "list" (default), "show", or "health"',
                         required: false
          param :worker_id, type: 'string', desc: 'Worker ID (for show action)', required: false
          param :status_filter, type: 'string', desc: 'Filter by lifecycle state (active/paused/retired)',
                                required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(action: 'list', worker_id: nil, status_filter: nil)
            case action.to_s
            when 'show'
              return 'worker_id is required for the "show" action.' unless worker_id

              handle_show(worker_id.strip)
            when 'health'
              handle_health
            else
              handle_list(status_filter)
            end
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach workers API).'
          rescue StandardError => e
            Legion::Logging.warn("WorkerStatus#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error fetching worker data: #{e.message}"
          end

          private

          def handle_list(status_filter)
            path = '/api/workers'
            path += "?lifecycle_state=#{status_filter}" if status_filter && !status_filter.strip.empty?
            data = api_get(path)
            workers = extract_collection(data)
            return 'No digital workers found.' if workers.empty?

            lines = ["Digital Workers (#{workers.size}):\n"]
            workers.each do |w|
              id = w[:worker_id] || w[:id]
              name = w[:name] || 'unnamed'
              state = w[:lifecycle_state] || 'unknown'
              tier = w[:risk_tier] || '-'
              lines << "  #{id} | #{name} | #{state} | risk: #{tier}"
            end
            lines.join("\n")
          end

          def handle_show(worker_id)
            data = api_get("/api/workers/#{worker_id}")
            w = data[:data] || data
            return "Worker #{worker_id} not found." if w[:error]

            lines = ["Worker: #{worker_id}\n"]
            display_fields(w).each { |key, val| lines << "  #{key}: #{val}" }
            lines.join("\n")
          end

          def handle_health
            data = api_get('/api/workers?health_status=unhealthy')
            unhealthy = extract_collection(data)

            data_all = api_get('/api/workers')
            all_workers = extract_collection(data_all)

            active = all_workers.count { |w| w[:lifecycle_state] == 'active' }
            paused = all_workers.count { |w| w[:lifecycle_state] == 'paused' }

            lines = ["Worker Health Summary:\n"]
            lines << "  Total:     #{all_workers.size}"
            lines << "  Active:    #{active}"
            lines << "  Paused:    #{paused}"
            lines << "  Unhealthy: #{unhealthy.size}"

            if unhealthy.any?
              lines << "\n  Unhealthy workers:"
              unhealthy.each do |w|
                lines << "    - #{w[:worker_id] || w[:id]}: #{w[:name] || 'unnamed'}"
              end
            end
            lines.join("\n")
          end

          def display_fields(worker)
            %i[name lifecycle_state risk_tier team extension_name owner_msid health_status
               created_at].filter_map do |key|
              [key, worker[key]] if worker[key]
            end
          end

          def extract_collection(data)
            entries = data[:data] || data
            entries.is_a?(Array) ? entries : []
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
