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
        class ManageTasks < RubyLLM::Tool
          description 'Interact with the Legion task system. List recent tasks, show task details ' \
                      'with metering data, view task logs, or trigger new tasks through the Ingress pipeline. ' \
                      'Use this to monitor job execution, check task status, and invoke extension runners.'
          param :action, type:     'string',
                         desc:     'Action to perform: "list", "show", "logs", or "trigger"',
                         required: true
          param :task_id, type:     'integer',
                          desc:     'Task ID (required for "show" and "logs")',
                          required: false
          param :runner_class, type:     'string',
                               desc:     'Full runner class name for "trigger" (e.g. "Legion::Extensions::Node::Runners::Info")',
                               required: false
          param :function, type:     'string',
                           desc:     'Function name for "trigger" (e.g. "execute")',
                           required: false
          param :payload, type:     'string',
                          desc:     'JSON payload for "trigger" action (optional)',
                          required: false
          param :status, type:     'string',
                         desc:     'Filter tasks by status for "list" (e.g. "completed", "failed", "pending")',
                         required: false
          param :limit, type:     'integer',
                        desc:     'Max results for "list" (default: 10)',
                        required: false

          VALID_ACTIONS = %w[list show logs trigger].freeze
          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(action:, **)
            action = action.to_s.strip
            return "Invalid action: #{action}. Use: #{VALID_ACTIONS.join(', ')}" unless VALID_ACTIONS.include?(action)

            send(:"handle_#{action}", **)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach task API).'
          rescue StandardError => e
            Legion::Logging.warn("ManageTasks#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error managing tasks: #{e.message}"
          end

          private

          def handle_list(status: nil, limit: nil, **)
            path = '/api/tasks'
            params = []
            params << "status=#{status}" if status
            params << "per_page=#{limit || 10}"
            path += "?#{params.join('&')}" unless params.empty?

            data = api_get(path)
            return "API error: #{data[:error]}" if data[:error]

            tasks = data[:data] || data[:items] || data
            tasks = [tasks] if tasks.is_a?(Hash)
            return 'No tasks found.' if !tasks.is_a?(Array) || tasks.empty?

            format_task_list(tasks)
          end

          def handle_show(task_id: nil, **)
            return 'task_id is required for "show"' unless task_id

            data = api_get("/api/tasks/#{task_id}")
            return "API error: #{data[:error]}" if data[:error]

            task = data[:data] || data
            format_task_detail(task)
          end

          def handle_logs(task_id: nil, **)
            return 'task_id is required for "logs"' unless task_id

            data = api_get("/api/tasks/#{task_id}/logs")
            return "API error: #{data[:error]}" if data[:error]

            logs = data[:data] || data[:items] || data
            logs = [logs] if logs.is_a?(Hash)
            return "No logs found for task #{task_id}." if !logs.is_a?(Array) || logs.empty?

            format_task_logs(task_id, logs)
          end

          def handle_trigger(runner_class: nil, function: nil, payload: nil, **)
            return 'runner_class is required for "trigger"' unless runner_class
            return 'function is required for "trigger"' unless function

            body = { runner_class: runner_class, function: function }
            body.merge!(::JSON.parse(payload, symbolize_names: true)) if payload

            data = api_post('/api/tasks', body)
            return "API error: #{data[:error]}" if data[:error]

            result = data[:data] || data
            "Task triggered successfully.\n  Task ID: #{result[:task_id]}\n  Runner: #{runner_class}\n  Function: #{function}"
          end

          def format_task_list(tasks)
            lines = ["Recent Tasks (#{tasks.size}):\n"]
            tasks.each do |t|
              status_str = t[:status] || 'unknown'
              lines << "  ##{t[:id]} [#{status_str}] #{t[:runner_class]}##{t[:function]} (#{t[:created_at]})"
            end
            lines.join("\n")
          end

          def format_task_detail(task)
            lines = ["Task ##{task[:id]}\n"]
            lines << "  Status: #{task[:status]}"
            lines << "  Runner: #{task[:runner_class]}"
            lines << "  Function: #{task[:function]}" if task[:function]
            lines << "  Created: #{task[:created_at]}"
            lines << "  Updated: #{task[:updated_at]}" if task[:updated_at]

            if task[:metering]
              m = task[:metering]
              lines << "\n  Metering:"
              lines << "    Total tokens: #{m[:total_tokens]}"
              lines << "    Input/Output: #{m[:input_tokens]}/#{m[:output_tokens]}"
              lines << "    Calls: #{m[:total_calls]}"
              lines << "    Avg latency: #{m[:avg_latency_ms]}ms"
              lines << "    Provider: #{Array(m[:provider]).join(', ')}" if m[:provider]
              lines << "    Model: #{Array(m[:model]).join(', ')}" if m[:model]
            end

            lines.join("\n")
          end

          def format_task_logs(task_id, logs)
            lines = ["Logs for Task ##{task_id} (#{logs.size} entries):\n"]
            logs.each do |log|
              ts = log[:created_at] || log[:timestamp]
              lines << "  [#{ts}] #{log[:level] || 'info'}: #{log[:message]}"
            end
            lines.join("\n")
          end

          def api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 10
            response = http.get(uri.request_uri)
            ::JSON.parse(response.body, symbolize_names: true)
          end

          def api_post(path, body)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 15
            request = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
            request.body = ::JSON.generate(body)
            response = http.request(request)
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
