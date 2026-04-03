# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Middleware
      class RequestLogger
        def initialize(app)
          @app = app
        end

        def call(env)
          method_path = "#{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
          Legion::Logging.info "[api][request-start] #{method_path}"
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          status, headers, body = @app.call(env)
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

          level = duration > 5000 ? :warn : :info
          Legion::Logging.send(level, "[api] #{method_path} #{status} #{duration}ms")
          [status, headers, body]
        rescue StandardError => e
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
          Legion::Logging.error "[api] #{method_path} 500 #{duration}ms - #{e.message}"
          raise
        end
      end
    end
  end
end
