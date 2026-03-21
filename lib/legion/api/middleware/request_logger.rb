# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Middleware
      class RequestLogger
        def initialize(app)
          @app = app
        end

        def call(env)
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          status, headers, body = @app.call(env)
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

          Legion::Logging.info "[api] #{env['REQUEST_METHOD']} #{env['PATH_INFO']} #{status} #{duration}ms"
          [status, headers, body]
        rescue StandardError => e
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
          Legion::Logging.error "[api] #{env['REQUEST_METHOD']} #{env['PATH_INFO']} 500 #{duration}ms - #{e.message}"
          raise
        end
      end
    end
  end
end
