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
          client_info = build_client_info(env)
          Legion::Logging.info "[api][request-start] #{method_path} #{client_info}"
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          status, headers, body = @app.call(env)
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

          level = duration > 5000 ? :warn : :info
          Legion::Logging.send(level, "[api] #{method_path} #{status} #{duration}ms #{client_info}")
          [status, headers, body]
        rescue StandardError => e
          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
          Legion::Logging.error "[api] #{method_path} 500 #{duration}ms #{client_info} - #{e.message}"
          raise
        end

        private

        def build_client_info(env)
          ip = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR'] || '-'
          ua = env['HTTP_USER_AGENT'] || '-'
          origin = env['HTTP_ORIGIN'] || '-'
          referer = env['HTTP_REFERER'] || '-'
          auth = env['HTTP_AUTHORIZATION'] ? 'Bearer(present)' : 'none'
          content_type = env['CONTENT_TYPE'] || '-'
          content_length = env['CONTENT_LENGTH'] || '-'
          query = env['QUERY_STRING'] && env['QUERY_STRING'].empty? ? nil : env['QUERY_STRING']

          parts = [
            "ip=#{ip}",
            "ua=#{ua}",
            "origin=#{origin}",
            "referer=#{referer}",
            "auth=#{auth}",
            "content_type=#{content_type}",
            "content_length=#{content_length}"
          ]
          parts << "query=#{query}" if query
          parts.join(' ')
        end

        def peek_body(env)
          input = env['rack.input']
          return '-' unless input.respond_to?(:read) && input.respond_to?(:rewind)

          begin
            input.rewind
            raw = input.read(1024)
            raw.to_s.gsub(/\s+/, ' ')[0, 512]
          rescue StandardError
            '-'
          ensure
            begin
              input.rewind
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
