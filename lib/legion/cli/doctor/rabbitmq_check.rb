# frozen_string_literal: true

require 'socket'

module Legion
  module CLI
    class Doctor
      class RabbitmqCheck
        DEFAULT_HOST = 'localhost'
        DEFAULT_PORT = 5672

        def name
          'RabbitMQ connection'
        end

        def run
          host = settings_host || DEFAULT_HOST
          port = settings_port || DEFAULT_PORT

          Socket.tcp(host, port, connect_timeout: 3, &:close)
          Result.new(name: name, status: :pass, message: "#{host}:#{port} reachable")
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
          Result.new(
            name:         name,
            status:       :fail,
            message:      "Cannot connect to #{host}:#{port}",
            prescription: 'Start RabbitMQ: `brew services start rabbitmq` or `systemctl start rabbitmq-server`'
          )
        rescue LoadError
          Result.new(name: name, status: :skip, message: 'socket not available')
        end

        private

        def settings_host
          return unless defined?(Legion::Settings)

          Legion::Settings[:transport]&.dig(:host)
        rescue StandardError => e
          Legion::Logging.debug("RabbitmqCheck#settings_host failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def settings_port
          return unless defined?(Legion::Settings)

          Legion::Settings[:transport]&.dig(:port)
        rescue StandardError => e
          Legion::Logging.debug("RabbitmqCheck#settings_port failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
