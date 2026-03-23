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
        class ViewEvents < RubyLLM::Tool
          description 'View recent events from the Legion event bus. Shows system events like task completions, ' \
                      'extension lifecycle, runner failures, worker state changes, and alerts. ' \
                      'Use this to understand what is happening in the running daemon right now.'
          param :count, type:     'integer',
                        desc:     'Number of recent events to fetch (default: 15, max: 100)',
                        required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(count: 15)
            count = count.to_i.clamp(1, 100)
            data = api_get("/api/events/recent?count=#{count}")
            return "API error: #{data[:error]}" if data[:error]

            events = data[:data] || data
            events = [events] if events.is_a?(Hash)
            return 'No recent events.' if !events.is_a?(Array) || events.empty?

            format_events(events)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach events API).'
          rescue StandardError => e
            Legion::Logging.warn("ViewEvents#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error fetching events: #{e.message}"
          end

          private

          def format_events(events)
            lines = ["Recent Events (#{events.size}):\n"]
            events.each do |ev|
              name = ev[:event] || ev['event'] || 'unknown'
              ts = ev[:timestamp] || ev['timestamp'] || ev[:at] || ev['at']
              detail = extract_detail(ev)
              entry = "  [#{ts}] #{name}"
              entry += " — #{detail}" if detail
              lines << entry
            end
            lines.join("\n")
          end

          def extract_detail(event)
            parts = []
            %i[extension worker_id status severity message rule].each do |key|
              val = event[key] || event[key.to_s]
              parts << "#{key}: #{val}" if val
            end
            parts.empty? ? nil : parts.join(', ')
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
