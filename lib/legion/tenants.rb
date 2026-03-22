# frozen_string_literal: true

module Legion
  module Tenants
    class << self
      def create(tenant_id:, name: nil, max_workers: 10, max_queue_depth: 10_000, **)
        return { error: 'tenant_exists' } if find(tenant_id)

        Legion::Data.connection[:tenants].insert(
          tenant_id:       tenant_id,
          name:            name || tenant_id,
          max_workers:     max_workers,
          max_queue_depth: max_queue_depth,
          status:          'active',
          created_at:      Time.now.utc,
          updated_at:      Time.now.utc
        )
        { created: true, tenant_id: tenant_id }
      end

      def find(tenant_id)
        Legion::Data.connection[:tenants].where(tenant_id: tenant_id).first
      rescue StandardError => e
        Legion::Logging.debug("Tenants#find failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      def suspend(tenant_id:, **)
        Legion::Data.connection[:tenants]
                    .where(tenant_id: tenant_id)
                    .update(status: 'suspended', updated_at: Time.now.utc)
        { suspended: true, tenant_id: tenant_id }
      end

      def list(**)
        Legion::Data.connection[:tenants].all
      end

      def check_quota(tenant_id:, resource:, **)
        tenant = find(tenant_id)
        return { allowed: true } unless tenant

        case resource
        when :workers
          count = Legion::Data.connection[:digital_workers].where(tenant_id: tenant_id).count
          { allowed: count < tenant[:max_workers], current: count, limit: tenant[:max_workers] }
        else
          { allowed: true }
        end
      end
    end
  end
end
