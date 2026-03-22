# frozen_string_literal: true

require 'sinatra/base'

module Legion
  class API < Sinatra::Base
    module Middleware
      class BodyLimit
        MAX_BODY_SIZE = 1_048_576 # 1MB

        def initialize(app, max_size: MAX_BODY_SIZE)
          @app = app
          @max_size = max_size
        end

        def call(env)
          content_length = env['CONTENT_LENGTH'].to_i
          if content_length > @max_size
            if defined?(Legion::Logging)
              Legion::Logging.warn "API body limit exceeded: #{content_length} bytes > #{@max_size} for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
            end
            body = Legion::JSON.dump({
                                       error: { code:    'payload_too_large',
                                                message: "request body exceeds #{@max_size} bytes" },
                                       meta:  { timestamp: Time.now.utc.iso8601 }
                                     })
            return [413, { 'content-type' => 'application/json' }, [body]]
          end
          @app.call(env)
        end
      end
    end
  end
end
