# frozen_string_literal: true

module Legion
  module DigitalWorker
    module RiskTier
      TIERS = %w[low medium high critical].freeze

      # Maps AIRB risk tiers to governance and consent constraints.
      # These constraints are enforced when a worker attempts to execute a task.
      CONSTRAINTS = {
        'low'      => { min_consent: 'notify',     governance_gate: false, council_required: false },
        'medium'   => { min_consent: 'consult',    governance_gate: false, council_required: false },
        'high'     => { min_consent: 'consult',    governance_gate: true,  council_required: true  },
        'critical' => { min_consent: 'supervised', governance_gate: true,  council_required: true  }
      }.freeze

      def self.valid?(tier)
        TIERS.include?(tier)
      end

      def self.constraints_for(tier)
        CONSTRAINTS.fetch(tier) { raise ArgumentError, "unknown risk tier: #{tier}. Valid: #{TIERS.join(', ')}" }
      end

      def self.min_consent(tier)
        constraints_for(tier)[:min_consent]
      end

      def self.governance_required?(tier)
        constraints_for(tier)[:governance_gate]
      end

      def self.council_required?(tier)
        constraints_for(tier)[:council_required]
      end

      # Assign or change a worker's risk tier. Lowering risk requires governance approval.
      def self.assign!(worker, tier:, by:, reason: nil)
        raise ArgumentError, "invalid tier: #{tier}" unless valid?(tier)

        old_tier = worker.risk_tier
        tier_lowered = old_tier && TIERS.index(tier) < TIERS.index(old_tier)

        if tier_lowered
          Legion::Logging.warn "[risk_tier] lowering risk from #{old_tier} to #{tier} requires governance approval"
          # In production: check governance approval here
        end

        worker.update(risk_tier: tier, updated_at: Time.now.utc)

        event = {
          event:     :risk_tier_changed,
          worker_id: worker.worker_id,
          from_tier: old_tier,
          to_tier:   tier,
          by:        by,
          reason:    reason,
          at:        Time.now.utc
        }

        Legion::Events.emit('worker.risk_tier_changed', **event) if defined?(Legion::Events)
        Legion::Logging.info "[risk_tier] worker=#{worker.worker_id} tier: #{old_tier || 'none'} -> #{tier} by=#{by}"

        { assigned: true }.merge(event)
      end

      # Validate that a worker's current consent tier meets the minimum for its risk tier
      def self.consent_compliant?(worker)
        return true unless worker.risk_tier

        min = min_consent(worker.risk_tier)
        hierarchy = Legion::DigitalWorker::Registry::CONSENT_HIERARCHY
        hierarchy.index(worker.consent_tier) >= hierarchy.index(min)
      end
    end
  end
end
