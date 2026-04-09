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
        class ListExtensions < RubyLLM::Tool
          description 'List loaded Legion extensions and their runners/functions. ' \
                      'Use this to discover what capabilities are available, what extensions are active, ' \
                      'and what tasks can be triggered through the framework.'
          param :extension_name, type: 'string',
                                 desc: 'Show runners for a specific extension by name (e.g. lex-node)', required: false
          param :state, type: 'string',
                        desc: 'Filter by state (e.g. "running"). Default: all', required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(extension_name: nil, state: nil)
            if extension_name
              fetch_extension_detail(extension_name)
            else
              fetch_extension_list(state)
            end
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot query extensions API).'
          rescue StandardError => e
            Legion::Logging.warn("ListExtensions#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error listing extensions: #{e.message}"
          end

          private

          def fetch_extension_list(state)
            path = '/api/extension_catalog'
            path += "?state=#{state}" if state
            data = api_get(path)
            return "API error: #{data[:error]}" if data[:error]

            extensions = data[:data] || data[:items] || data
            extensions = [extensions] if extensions.is_a?(Hash)
            return 'No extensions found.' if extensions.empty?

            format_list(extensions)
          end

          def fetch_extension_detail(name)
            ext_data = api_get("/api/extension_catalog/#{name}")
            return "API error: #{ext_data[:error]}" if ext_data[:error]

            runners_data = api_get("/api/extension_catalog/#{name}/runners")
            runners = runners_data[:data] || runners_data[:items] || runners_data
            runners = [runners] if runners.is_a?(Hash)
            runners = [] unless runners.is_a?(Array)

            format_detail(ext_data[:data] || ext_data, runners)
          end

          def format_list(extensions)
            lines = ["Loaded Extensions (#{extensions.size}):\n"]
            extensions.each do |ext|
              lines << "  #{ext[:name]} (#{ext[:state]})"
            end
            lines.join("\n")
          end

          def format_detail(ext, runners)
            lines = ["Extension: #{ext[:name]}\n"]
            lines << "  State: #{ext[:state]}"
            lines << "  Version: #{ext[:version]}" if ext[:version]

            if runners.any?
              lines << "\n  Runners (#{runners.size}):"
              runners.each do |r|
                lines << "    #{r[:name]} (#{r[:runner_class]})"
              end
            else
              lines << "\n  No runners registered."
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
