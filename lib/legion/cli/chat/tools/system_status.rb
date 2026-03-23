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
        class SystemStatus < RubyLLM::Tool
          description 'Check the health and status of the Legion daemon. Shows component readiness ' \
                      '(settings, crypt, transport, cache, data, gaia, extensions, api), ' \
                      'extension count, uptime, and version info. Use this to diagnose issues or verify the system is healthy.'

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute
            health = fetch_health
            ready = fetch_ready
            format_status(health, ready)
          rescue Errno::ECONNREFUSED
            format('Legion daemon not running (cannot connect to API on port %d).', api_port)
          rescue StandardError => e
            Legion::Logging.warn("SystemStatus#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error checking system status: #{e.message}"
          end

          private

          def fetch_health
            api_get('/api/health')
          rescue Errno::ECONNREFUSED
            raise
          rescue StandardError
            nil
          end

          def fetch_ready
            api_get('/api/ready')
          rescue Errno::ECONNREFUSED
            raise
          rescue StandardError
            nil
          end

          def format_status(health, ready)
            lines = ["Legion System Status\n"]

            if health
              lines << "  Status: #{health[:status] || 'unknown'}"
              lines << "  Version: #{health[:version]}" if health[:version]
              lines << "  Node: #{health[:node]}" if health[:node]
              lines << "  Uptime: #{format_uptime(health[:uptime_seconds])}" if health[:uptime_seconds]
              lines << "  PID: #{health[:pid]}" if health[:pid]
            else
              lines << '  Health endpoint: unreachable'
            end

            if ready
              components = ready[:components] || ready[:data] || {}
              if components.is_a?(Hash) && components.any?
                lines << "\n  Components:"
                components.each do |name, status|
                  icon = status == true ? 'ready' : 'not ready'
                  lines << "    #{name}: #{icon}"
                end
                ready_count = components.values.count(true)
                lines << "  Overall: #{ready_count}/#{components.size} ready"
              end

              lines << "  Extensions: #{ready[:extension_count]}" if ready[:extension_count]
            end

            lines.join("\n")
          end

          def format_uptime(seconds)
            return 'unknown' unless seconds

            seconds = seconds.to_i
            days = seconds / 86_400
            hours = (seconds % 86_400) / 3600
            mins = (seconds % 3600) / 60
            parts = []
            parts << "#{days}d" if days.positive?
            parts << "#{hours}h" if hours.positive?
            parts << "#{mins}m" if mins.positive?
            parts << "#{seconds % 60}s" if parts.empty?
            parts.join(' ')
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
