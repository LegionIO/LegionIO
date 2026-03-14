# frozen_string_literal: true

module Legion
  module DigitalWorker
    module Registry
      class WorkerNotFound     < StandardError; end
      class WorkerNotActive    < StandardError; end
      class InsufficientConsent < StandardError; end

      CONSENT_HIERARCHY = %w[supervised consult notify autonomous].freeze

      def self.validate_execution!(worker_id:, required_consent: nil)
        worker = Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)

        unless worker
          emit_blocked(worker_id: worker_id, reason: 'unregistered')
          raise WorkerNotFound, "no registered worker with id #{worker_id}"
        end

        unless worker.active?
          emit_blocked(worker_id: worker_id, reason: "lifecycle_state=#{worker.lifecycle_state}")
          raise WorkerNotActive, "worker #{worker_id} is #{worker.lifecycle_state}, not active"
        end

        if required_consent && !consent_sufficient?(worker.consent_tier, required_consent)
          emit_blocked(worker_id: worker_id, reason: "consent=#{worker.consent_tier} < #{required_consent}")
          raise InsufficientConsent,
                "worker #{worker_id} consent tier #{worker.consent_tier} insufficient (needs #{required_consent})"
        end

        worker
      end

      def self.consent_sufficient?(current_tier, required_tier)
        CONSENT_HIERARCHY.index(current_tier) >= CONSENT_HIERARCHY.index(required_tier)
      end

      def self.emit_blocked(worker_id:, reason:)
        return unless defined?(Legion::Events)

        Legion::Events.emit('worker.blocked', {
                              worker_id: worker_id,
                              reason:    reason,
                              at:        Time.now.utc
                            })
      end

      private_class_method :emit_blocked
    end
  end
end
