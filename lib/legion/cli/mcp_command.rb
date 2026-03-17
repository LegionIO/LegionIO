# frozen_string_literal: true

module Legion
  module CLI
    class Mcp < Thor
      def self.exit_on_failure?
        true
      end

      desc 'stdio', 'Start MCP server with stdio transport (default)'
      def stdio
        require 'legion/mcp'

        server = Legion::MCP.server
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        transport.open
      end

      desc 'http', 'Start MCP server with streamable HTTP transport'
      option :port, type: :numeric, default: 9393, desc: 'Port to listen on'
      option :host, type: :string, default: 'localhost', desc: 'Host to bind to'
      def http
        require 'legion/mcp'
        require 'rackup'

        server = Legion::MCP.server
        transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(server)
        server.transport = transport

        app = build_rack_app(transport)

        warn "Legion MCP server listening on http://#{options[:host]}:#{options[:port]}"
        Rackup::Handler.get('puma').run(app, Port: options[:port], Host: options[:host])
      end

      default_command :stdio

      no_commands do
        private

        def build_rack_app(transport)
          Rack::Builder.new do
            run lambda { |env|
              req = Rack::Request.new(env)
              if Legion::MCP::Auth.auth_enabled?
                token = req.get_header('HTTP_AUTHORIZATION')&.sub(/\ABearer /i, '')
                auth = Legion::MCP::Auth.authenticate(token)
                unless auth[:authenticated]
                  next [401, { 'content-type' => 'application/json' },
                        [Legion::JSON.dump({ error: auth[:error] })]]
                end
              end
              transport.handle_request(req)
            }
          end
        end
      end
    end
  end
end
