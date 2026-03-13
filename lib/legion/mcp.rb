# frozen_string_literal: true

require 'mcp'
require 'legion/json'

require_relative 'mcp/server'

module Legion
  module MCP
    class << self
      def server
        @server ||= Server.build
      end

      def reset!
        @server = nil
      end
    end
  end
end
