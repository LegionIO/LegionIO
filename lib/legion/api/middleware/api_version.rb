# frozen_string_literal: true

require 'sinatra/base'

module Legion
  class API < Sinatra::Base
    module Middleware
      class ApiVersion
        SKIP_PATHS = %w[/api/health /api/ready /api/openapi.json /metrics].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          path = env['PATH_INFO']

          if path.start_with?('/api/v1/')
            env['PATH_INFO'] = path.sub('/api/v1/', '/api/')
            env['HTTP_X_API_VERSION'] = '1'
            @app.call(env)
          elsif path.start_with?('/api/') && !skip_path?(path)
            status, headers, body = @app.call(env)
            headers['Deprecation'] = 'true'
            headers['Sunset'] = (Time.now + (180 * 86_400)).httpdate
            successor = path.sub('/api/', '/api/v1/')
            headers['Link'] = "<#{successor}>; rel=\"successor-version\""
            [status, headers, body]
          else
            @app.call(env)
          end
        end

        private

        def skip_path?(path)
          SKIP_PATHS.any? { |skip| path.start_with?(skip) }
        end
      end
    end
  end
end
