# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Legion
  module CLI
    # Shared HTTP client for CLI commands that talk to the running daemon API.
    # Include this module inside a Thor command's `no_commands` block, or
    # extend it at the class level, to get api_get / api_post / api_put /
    # api_delete helpers that target http://127.0.0.1:<port>/api/*.
    module ApiClient
      def api_port
        Connection.ensure_settings
        api_settings = Legion::Settings[:api]
        (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
      rescue StandardError
        4567
      end

      def api_get(path)
        uri = URI("http://127.0.0.1:#{api_port}#{path}")
        http = build_http(uri)
        response = http.get(uri.request_uri)
        handle_response(response, path)
      rescue Errno::ECONNREFUSED
        daemon_not_running!
      rescue SystemExit
        raise
      rescue StandardError => e
        api_error!(e, path)
      end

      def api_post(path, **payload)
        uri = URI("http://127.0.0.1:#{api_port}#{path}")
        http = build_http(uri, read_timeout: 300)
        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = ::JSON.generate(payload)
        response = http.request(request)
        handle_response(response, path)
      rescue Errno::ECONNREFUSED
        daemon_not_running!
      rescue SystemExit
        raise
      rescue StandardError => e
        api_error!(e, path)
      end

      def api_put(path, **payload)
        uri = URI("http://127.0.0.1:#{api_port}#{path}")
        http = build_http(uri)
        request = Net::HTTP::Put.new(uri.path, 'Content-Type' => 'application/json')
        request.body = ::JSON.generate(payload)
        response = http.request(request)
        handle_response(response, path)
      rescue Errno::ECONNREFUSED
        daemon_not_running!
      rescue SystemExit
        raise
      rescue StandardError => e
        api_error!(e, path)
      end

      def api_delete(path)
        uri = URI("http://127.0.0.1:#{api_port}#{path}")
        http = build_http(uri)
        response = http.delete(uri.path)
        handle_response(response, path)
      rescue Errno::ECONNREFUSED
        daemon_not_running!
      rescue SystemExit
        raise
      rescue StandardError => e
        api_error!(e, path)
      end

      private

      def build_http(uri, read_timeout: 10)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3
        http.read_timeout = read_timeout
        http
      end

      def handle_response(response, path)
        unless response.is_a?(Net::HTTPSuccess)
          formatter.error("API returned #{response.code} for #{path}")
          raise SystemExit, 1
        end
        body = ::JSON.parse(response.body, symbolize_names: true)
        body[:data]
      end

      def daemon_not_running!
        formatter.error('Daemon not running. Start with: legionio start')
        raise SystemExit, 1
      end

      def api_error!(err, path)
        formatter.error("API request failed (#{path}): #{err.message}")
        raise SystemExit, 1
      end
    end
  end
end
