# frozen_string_literal: true

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
        class DetectAnomalies < Legion::Tools::Base
          tool_name 'legion.detect_anomalies'
          description 'Detect anomalies in recent task execution metrics by comparing the last hour against ' \
                      'the previous 23-hour baseline. Reports cost spikes, latency increases, and failure rate ' \
                      'changes. Use this proactively to check system health or when investigating issues.'
          input_schema({
                         type:       'object',
                         properties: {
                           threshold: { type: 'number' }
                         },
                         required:   ['threshold']
                       })

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def self.call(threshold: 2.0)
            data = api_get("/api/traces/anomalies?threshold=#{threshold.to_f}")
            return "API error: #{data[:error][:message]}" if data[:error]

            format_report(data[:data] || data)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach anomaly detection API).'
          rescue StandardError => e
            Legion::Logging.warn("DetectAnomalies#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error detecting anomalies: #{e.message}"
          end

          def self.format_report(data)
            anomalies = data[:anomalies] || []
            lines = ["Anomaly Report (threshold: #{data[:threshold] || '2.0'}x)\n"]
            lines << "  Recent period:   #{data[:recent_period] || 'last 1 hour'} (#{data[:recent_count] || 0} records)"
            lines << "  Baseline period: #{data[:baseline_period] || 'previous 23 hours'} (#{data[:baseline_count] || 0} records)"
            lines << ''

            if anomalies.empty?
              lines << 'No anomalies detected. All metrics within normal range.'
            else
              lines << "#{anomalies.size} anomal#{anomalies.size == 1 ? 'y' : 'ies'} detected:\n"
              anomalies.each_with_index do |a, i|
                severity = (a[:severity] || 'warning').upcase
                lines << "  #{i + 1}. [#{severity}] #{a[:metric]}"
                lines << "     Recent: #{a[:recent]} | Baseline: #{a[:baseline]} | Ratio: #{a[:ratio]}x"
              end
            end

            lines.join("\n")
          end

          def self.api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            response = http.get(uri.request_uri)
            ::JSON.parse(response.body, symbolize_names: true)
          end

          def self.api_port
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
