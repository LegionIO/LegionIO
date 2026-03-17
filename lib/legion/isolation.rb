# frozen_string_literal: true

module Legion
  module Isolation
    class Context
      attr_reader :agent_id, :tenant_id, :allowed_tools, :risk_tier

      def initialize(agent_id:, tenant_id: nil, allowed_tools: [], risk_tier: :standard)
        @agent_id = agent_id
        @tenant_id = tenant_id
        @allowed_tools = allowed_tools.map(&:to_s).freeze
        @risk_tier = risk_tier.to_sym
      end

      def tool_allowed?(tool_name)
        allowed_tools.empty? || allowed_tools.include?(tool_name.to_s)
      end

      def data_filter
        filter = { agent_id: agent_id }
        filter[:tenant_id] = tenant_id if tenant_id
        filter
      end
    end

    class << self
      def current
        Thread.current[:legion_isolation_context]
      end

      def with_context(context)
        previous = Thread.current[:legion_isolation_context]
        Thread.current[:legion_isolation_context] = context
        yield
      ensure
        Thread.current[:legion_isolation_context] = previous
      end

      def enforce_tool_access!(tool_name)
        ctx = current
        return true unless ctx

        raise SecurityError, "Agent #{ctx.agent_id} not authorized for tool: #{tool_name}" unless ctx.tool_allowed?(tool_name)

        true
      end
    end
  end
end
