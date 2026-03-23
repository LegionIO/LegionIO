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
        class KnowledgeMaintenance < RubyLLM::Tool
          description 'Run maintenance operations on the Apollo knowledge graph. ' \
                      'Use decay_cycle to reduce confidence of old or uncorroborated entries over time. ' \
                      'Use corroboration to cross-verify entries and boost confidence of mutually supporting facts.'
          param :action, type: 'string',
                         desc: 'Maintenance action: "decay_cycle" (age-based confidence decay) or "corroboration" (cross-verify entries)'

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'
          VALID_ACTIONS = %w[decay_cycle corroboration].freeze

          def execute(action:)
            action = action.to_s.strip
            return "Invalid action: #{action}. Must be one of: #{VALID_ACTIONS.join(', ')}" unless VALID_ACTIONS.include?(action)

            data = run_maintenance(action)
            return "Apollo error: #{data[:error]}" if data[:error]

            format_result(action, data)
          rescue Errno::ECONNREFUSED
            'Apollo unavailable (daemon not running).'
          rescue StandardError => e
            Legion::Logging.warn("KnowledgeMaintenance#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error running maintenance: #{e.message}"
          end

          private

          def run_maintenance(action)
            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}/api/apollo/maintenance")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 30
            req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            req.body = ::JSON.dump({ action: action })
            response = http.request(req)
            parsed = ::JSON.parse(response.body, symbolize_names: true)
            parsed[:data] || parsed
          end

          def apollo_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end

          def format_result(action, data)
            case action
            when 'decay_cycle'
              format_decay_result(data)
            when 'corroboration'
              format_corroboration_result(data)
            else
              "Maintenance completed: #{data.inspect}"
            end
          end

          def format_decay_result(data)
            decayed = data[:decayed_count] || data[:decayed] || 0
            removed = data[:removed_count] || data[:removed] || 0
            header = "Decay cycle complete:\n"
            header += "  Entries decayed: #{decayed}\n"
            header += "  Entries removed (below threshold): #{removed}\n"
            header += "  Duration: #{data[:duration_ms]}ms" if data[:duration_ms]
            header
          end

          def format_corroboration_result(data)
            checked = data[:checked_count] || data[:checked] || 0
            boosted = data[:boosted_count] || data[:boosted] || 0
            header = "Corroboration check complete:\n"
            header += "  Entries checked: #{checked}\n"
            header += "  Entries boosted (mutually supporting): #{boosted}\n"
            header += "  Duration: #{data[:duration_ms]}ms" if data[:duration_ms]
            header
          end
        end
      end
    end
  end
end
