# frozen_string_literal: true

module Legion
  module Compliance
    module PhiAccessLog
      class << self
        def log_access(resource:, action:, actor:, reason:)
          return unless Legion::Compliance.phi_enabled?
          return unless defined?(Legion::Audit)

          Legion::Audit.record(
            event_type:   'phi_access',
            principal_id: actor,
            action:       action,
            resource:     resource,
            detail:       { reason: reason, phi: true }
          )
        rescue StandardError => e
          Legion::Logging.error "[Compliance] PhiAccessLog#log_access failed: #{e.message}" if defined?(Legion::Logging)
        end
      end
    end
  end
end
