# frozen_string_literal: true

return unless defined?(Legion::Extensions::Actors::Every)

module Legion
  module Extensions
    module Agentic
      module Consent
        module Actor
          class TierEvaluation < Legion::Extensions::Actors::Every
            # Run tier evaluation and pending approval expiry every hour
            INTERVAL = 3600

            def perform
              expire_stale_approvals
              evaluate_pending_workers
            rescue StandardError => e
              Legion::Logging.error "[TierEvaluation] perform failed: #{e.message}" if defined?(Legion::Logging)
            end

            private

            def expire_stale_approvals
              return unless runner_available?

              runner = runner_instance
              ttl_hours = Legion::Settings.dig(:consent, :pending_ttl_hours) || 72
              result = runner.expire_pending_approvals(ttl_hours: ttl_hours)
              return unless result[:expired].to_i.positive? && defined?(Legion::Logging)

              Legion::Logging.info "[TierEvaluation] expired #{result[:expired]} stale consent requests"
            rescue StandardError => e
              Legion::Logging.warn "[TierEvaluation] expire_stale_approvals failed: #{e.message}" if defined?(Legion::Logging)
            end

            def evaluate_pending_workers
              return unless defined?(Legion::Data::Model::DigitalWorker)
              return unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)

              # Find active workers that may be eligible for autonomous tier promotion
              # but do not yet have a pending approval request.
              active_workers = Legion::Data::Model::DigitalWorker
                               .where(lifecycle_state: 'active')
                               .exclude(consent_tier: 'autonomous')
                               .all

              active_workers.each do |worker|
                evaluate_worker_for_promotion(worker)
              rescue StandardError => e
                Legion::Logging.warn "[TierEvaluation] evaluate failed for worker=#{worker.worker_id}: #{e.message}" if defined?(Legion::Logging)
              end
            rescue StandardError => e
              Legion::Logging.warn "[TierEvaluation] evaluate_pending_workers failed: #{e.message}" if defined?(Legion::Logging)
            end

            def evaluate_worker_for_promotion(worker)
              return unless promotion_eligible?(worker)
              return if pending_request_exists?(worker.worker_id)

              from_tier = worker.consent_tier
              to_tier   = next_tier(from_tier)
              return unless to_tier

              runner = runner_instance
              runner.request_promotion(
                worker_id:    worker.worker_id,
                from_tier:    from_tier,
                to_tier:      to_tier,
                requested_by: 'system:tier_evaluation'
              )
            end

            def promotion_eligible?(worker)
              return false unless worker.trust_score.to_f >= trust_threshold
              return false unless (worker.risk_tier || 'low') == 'low'

              true
            end

            def trust_threshold
              Legion::Settings.dig(:consent, :promotion_trust_threshold) || 0.85
            rescue StandardError
              0.85
            end

            def next_tier(current_tier)
              hierarchy = %w[supervised inform consult autonomous]
              idx = hierarchy.index(current_tier)
              return nil unless idx
              return nil if idx >= hierarchy.length - 1

              hierarchy[idx + 1]
            end

            def pending_request_exists?(worker_id)
              Legion::Extensions::Agentic::Consent::Models::ConsentMap
                .pending_for_worker(worker_id).count.positive?
            end

            def runner_available?
              defined?(Legion::Extensions::Agentic::Consent::Runners::Consent)
            end

            def runner_instance
              Object.new.extend(Legion::Extensions::Agentic::Consent::Runners::Consent)
            end
          end
        end
      end
    end
  end
end
