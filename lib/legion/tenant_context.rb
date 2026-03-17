# frozen_string_literal: true

module Legion
  module TenantContext
    class << self
      def current
        Thread.current[:legion_tenant_id]
      end

      def set(tenant_id)
        Thread.current[:legion_tenant_id] = tenant_id
      end

      def clear
        Thread.current[:legion_tenant_id] = nil
      end

      def with(tenant_id)
        prev = current
        set(tenant_id)
        yield
      ensure
        set(prev)
      end
    end
  end
end
