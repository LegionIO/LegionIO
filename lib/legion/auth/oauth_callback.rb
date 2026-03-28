# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'uri'

module Legion
  module Auth
    class OauthCallback
      DEFAULT_TIMEOUT = 120
      LOCALHOST       = '127.0.0.1'

      attr_reader :port, :redirect_uri

      def initialize(timeout: DEFAULT_TIMEOUT)
        @timeout  = timeout
        @server   = TCPServer.new(LOCALHOST, 0)
        @port     = @server.addr[1]
        @redirect_uri = "http://#{LOCALHOST}:#{@port}/callback"
      end

      def wait_for_callback
        Timeout.timeout(@timeout) do
          client = @server.accept
          request_line = client.gets
          parse_callback(request_line, client)
        end
      ensure
        @server.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def close
        @server.close rescue nil # rubocop:disable Style/RescueModifier
      end

      private

      def parse_callback(request_line, client)
        send_response(client)
        return {} unless request_line&.start_with?('GET')

        path = request_line.split[1] || ''
        query_string = path.split('?', 2)[1] || ''
        params = URI.decode_www_form(query_string).to_h
        params.transform_keys(&:to_sym)
      end

      def send_response(client)
        body = '<html><body><h1>Authorization complete.</h1><p>You may close this window.</p></body></html>'
        client.puts 'HTTP/1.1 200 OK'
        client.puts 'Content-Type: text/html'
        client.puts "Content-Length: #{body.bytesize}"
        client.puts 'Connection: close'
        client.puts
        client.puts body
      rescue Errno::ECONNRESET, Errno::EPIPE, IOError
        nil
      ensure
        client.close rescue nil # rubocop:disable Style/RescueModifier
      end
    end
  end
end
