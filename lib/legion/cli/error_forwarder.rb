# frozen_string_literal: true

require 'net/http'

module Legion
  module CLI
    module ErrorForwarder
      module_function

      def forward_error(exception, command: nil)
        payload = {
          level:           'error',
          message:         exception.message.to_s,
          exception_class: exception.class.name,
          backtrace:       Array(exception.backtrace).first(10),
          component_type:  'cli',
          source:          ::File.basename($PROGRAM_NAME)
        }
        payload[:command] = command if command
        post_to_daemon(payload)
      rescue StandardError
        # silently swallow — forwarding must never crash the CLI
      end

      def forward_warning(message, command: nil)
        payload = {
          level:          'warn',
          message:        message.to_s,
          component_type: 'cli',
          source:         ::File.basename($PROGRAM_NAME)
        }
        payload[:command] = command if command
        post_to_daemon(payload)
      rescue StandardError
        # silently swallow — forwarding must never crash the CLI
      end

      def post_to_daemon(payload)
        port = daemon_port
        uri  = URI("http://localhost:#{port}/api/logs")

        http              = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2
        http.read_timeout = 2

        request      = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = ::JSON.generate(payload)

        http.request(request)
      rescue StandardError
        nil
      end

      def daemon_port
        require 'legion/settings'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        api_settings = Legion::Settings[:api]
        (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
      rescue StandardError
        4567
      end
    end
  end
end
