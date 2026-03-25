# frozen_string_literal: true

module Legion
  module Compliance
    module PhiErasure
      class << self
        def erase(task_id:, reason:)
          result = { task_id: task_id, erased: false, steps: {} }

          result[:steps][:key_erasure] = erase_key(task_id)
          result[:steps][:cache_purge] = purge_cache(task_id)
          log_erasure(task_id: task_id, reason: reason)
          result[:steps][:verification] = verify_erasure(task_id)

          key_result    = result[:steps][:key_erasure]
          verify_result = result[:steps][:verification]

          result[:erased] = key_result.nil? || (key_result.is_a?(Hash) && key_result[:erased] != false &&
            verify_result.is_a?(Hash) && verify_result[:erased] != false)
          result
        rescue StandardError => e
          Legion::Logging.error "[Compliance] PhiErasure#erase failed task_id=#{task_id}: #{e.message}" if defined?(Legion::Logging)
          { task_id: task_id, erased: false, error: e.message }
        end

        private

        def erase_key(task_id)
          return nil unless defined?(Legion::Crypt::Erasure)

          Legion::Crypt::Erasure.erase_tenant(tenant_id: task_id)
        end

        def purge_cache(task_id)
          return nil unless defined?(Legion::Cache)

          prefix = "phi:#{task_id}:"
          Legion::Cache.delete(prefix)
          { purged: true, prefix: prefix }
        rescue StandardError => e
          { purged: false, error: e.message }
        end

        def log_erasure(task_id:, reason:)
          return unless defined?(Legion::Compliance::PhiAccessLog)

          Legion::Compliance::PhiAccessLog.log_access(
            resource: task_id,
            action:   'erasure',
            actor:    'system:phi_erasure',
            reason:   reason
          )
        end

        def verify_erasure(task_id)
          return nil unless defined?(Legion::Crypt::Erasure)

          Legion::Crypt::Erasure.verify_erasure(tenant_id: task_id)
        end
      end
    end
  end
end
