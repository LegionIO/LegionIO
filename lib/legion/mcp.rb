# frozen_string_literal: true

require 'mcp'
require 'legion/json'

require_relative 'mcp/auth'
require_relative 'mcp/tool_governance'
require_relative 'mcp/server'

module Legion
  module MCP
    class << self
      def server
        @server ||= Server.build
      end

      def server_for(token:)
        auth_result = Auth.authenticate(token)
        return { error: auth_result[:error] } unless auth_result[:authenticated]

        Server.build(identity: auth_result[:identity])
      end

      def reset!
        @server = nil
      end
    end
  end
end
