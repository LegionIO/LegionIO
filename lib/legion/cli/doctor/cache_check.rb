# frozen_string_literal: true

require 'socket'

module Legion
  module CLI
    class Doctor
      class CacheCheck
        def name
          'Cache backend'
        end

        def run
          backend, host, port = read_cache_config
          return Result.new(name: name, status: :skip, message: 'No cache backend configured') if backend.nil?

          check_connection(backend, host, port)
        end

        private

        def read_cache_config
          return [nil, nil, nil] unless defined?(Legion::Settings)

          cache = Legion::Settings[:cache]
          return [nil, nil, nil] unless cache.is_a?(Hash)

          backend = (cache[:backend] || cache[:driver])&.to_s
          return [nil, nil, nil] if backend.nil? || backend.empty?

          host = cache[:host] || 'localhost'
          port = cache_port(backend, cache)
          [backend, host.to_s, port]
        rescue StandardError
          [nil, nil, nil]
        end

        def cache_port(backend, cache)
          return cache[:port].to_i if cache[:port]

          case backend
          when 'redis'     then 6379
          when 'memcached' then 11_211
          end
        end

        def check_connection(backend, host, port)
          return Result.new(name: name, status: :skip, message: "#{backend}: no port configured") if port.nil?

          Socket.tcp(host, port, connect_timeout: 3, &:close)
          Result.new(name: name, status: :pass, message: "#{backend} #{host}:#{port} reachable")
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
          Result.new(
            name:         name,
            status:       :fail,
            message:      "#{backend} not reachable at #{host}:#{port}",
            prescription: "Check #{backend} configuration or start the service"
          )
        end
      end
    end
  end
end
