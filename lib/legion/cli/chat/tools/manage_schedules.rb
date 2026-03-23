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
        class ManageSchedules < RubyLLM::Tool
          description 'Manage scheduled tasks on the running Legion daemon. List active schedules, ' \
                      'show schedule details, view run logs, or create new cron/interval schedules. ' \
                      'Use this to automate recurring tasks.'
          param :action, type:     'string',
                         desc:     'Action: "list", "show", "logs", or "create"',
                         required: true
          param :schedule_id, type: 'string', desc: 'Schedule ID (for show/logs)', required: false
          param :function_id, type: 'string', desc: 'Function ID to schedule (for create)', required: false
          param :cron, type: 'string', desc: 'Cron expression (for create, e.g. "0 * * * *")', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'
          VALID_ACTIONS = %w[list show logs create].freeze

          def execute(action:, **)
            action = action.to_s.strip
            return "Invalid action: #{action}. Use: #{VALID_ACTIONS.join(', ')}" unless VALID_ACTIONS.include?(action)

            send(:"handle_#{action}", **)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach schedules API).'
          rescue StandardError => e
            Legion::Logging.warn("ManageSchedules#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error managing schedules: #{e.message}"
          end

          private

          def handle_list(**)
            data = api_get('/api/schedules')
            entries = extract_collection(data)
            return 'No schedules found.' if entries.empty?

            lines = ["Schedules (#{entries.size}):\n"]
            entries.each do |s|
              schedule = s[:cron] || "every #{s[:interval]}s"
              status = s[:active] ? 'active' : 'inactive'
              lines << "  ##{s[:id]} [#{status}] #{schedule} -> function #{s[:function_id] || '?'}"
              lines << "    #{s[:description]}" if s[:description]
            end
            lines.join("\n")
          end

          def handle_show(schedule_id: nil, **)
            return 'schedule_id is required for the "show" action.' unless schedule_id

            data = api_get("/api/schedules/#{schedule_id}")
            s = data[:data] || data
            return "Schedule ##{schedule_id} not found." if s[:error]

            lines = ["Schedule ##{schedule_id}:\n"]
            s.each { |key, val| lines << "  #{key}: #{val}" unless val.nil? }
            lines.join("\n")
          end

          def handle_logs(schedule_id: nil, **)
            return 'schedule_id is required for the "logs" action.' unless schedule_id

            data = api_get("/api/schedules/#{schedule_id}/logs")
            entries = extract_collection(data)
            return "No logs for schedule ##{schedule_id}." if entries.empty?

            lines = ["Logs for Schedule ##{schedule_id} (#{entries.size}):\n"]
            entries.first(10).each do |log|
              lines << "  [#{log[:started_at]}] #{log[:status] || '?'}: #{log[:message] || '-'}"
            end
            lines.join("\n")
          end

          def handle_create(function_id: nil, cron: nil, **)
            return 'function_id is required for the "create" action.' unless function_id
            return 'cron expression is required for the "create" action.' unless cron

            data = api_post('/api/schedules', { function_id: function_id.to_i, cron: cron })
            s = data[:data] || data
            return "Failed to create schedule: #{s[:error]}" if s[:error]

            "Schedule created (id: #{s[:id]}, cron: #{cron}, function: #{function_id})"
          end

          def extract_collection(data)
            entries = data[:data] || data
            entries = [entries] if entries.is_a?(Hash) && !entries.key?(:error)
            Array(entries).reject { |e| e.is_a?(Hash) && e.key?(:error) }
          end

          def api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            response = http.get(uri.request_uri)
            ::JSON.parse(response.body, symbolize_names: true)
          end

          def api_post(path, body)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            req.body = ::JSON.dump(body)
            response = http.request(req)
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
