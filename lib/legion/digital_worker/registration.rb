# frozen_string_literal: true

require 'securerandom'

module Legion
  module DigitalWorker
    module Registration
      APPROVAL_TIMEOUT_SECONDS = 172_800 # 48 hours default

      class << self
        def register(worker_attrs)
          risk_tier = worker_attrs[:risk_tier].to_s

          lifecycle_state = if approval_required?(risk_tier)
                              'pending_approval'
                            else
                              'bootstrap'
                            end

          worker = Legion::Data::Model::DigitalWorker.create(
            worker_id:       SecureRandom.uuid,
            name:            worker_attrs[:name],
            extension_name:  worker_attrs[:extension_name],
            entra_app_id:    worker_attrs[:entra_app_id],
            owner_msid:      worker_attrs[:owner_msid],
            owner_name:      worker_attrs[:owner_name],
            business_role:   worker_attrs[:business_role],
            risk_tier:       risk_tier.empty? ? nil : risk_tier,
            team:            worker_attrs[:team],
            manager_msid:    worker_attrs[:manager_msid],
            lifecycle_state: lifecycle_state,
            consent_tier:    'supervised',
            trust_score:     0.0
          )

          if lifecycle_state == 'pending_approval'
            intake_id = create_airb_intake(worker)
            log_info "worker=#{worker.worker_id} state=pending_approval airb_intake=#{intake_id}"
            emit_event('worker.registration.pending', worker_id: worker.worker_id, risk_tier: risk_tier, intake_id: intake_id)
          else
            log_info "worker=#{worker.worker_id} state=bootstrap risk_tier=#{risk_tier}"
            emit_event('worker.registration.created', worker_id: worker.worker_id, risk_tier: risk_tier)
          end

          worker
        end

        def approve(worker_id, approver:, notes: nil)
          worker = find_pending!(worker_id)

          Lifecycle.transition!(
            worker,
            to_state:           'active',
            by:                 approver,
            reason:             notes,
            authority_verified: true
          )

          record_audit('worker_approved', worker_id, approver, { notes: notes })
          emit_event('worker.registration.approved', worker_id: worker_id, approver: approver)
          log_info "worker=#{worker_id} approved by=#{approver}"

          worker
        end

        def reject(worker_id, approver:, reason:)
          worker = find_pending!(worker_id)

          Lifecycle.transition!(
            worker,
            to_state:           'rejected',
            by:                 approver,
            reason:             reason,
            authority_verified: true
          )

          record_audit('worker_rejected', worker_id, approver, { reason: reason })
          emit_event('worker.registration.rejected', worker_id: worker_id, approver: approver, reason: reason)
          log_info "worker=#{worker_id} rejected by=#{approver} reason=#{reason}"

          worker
        end

        def pending_approvals
          return [] unless defined?(Legion::Data::Model::DigitalWorker)

          Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'pending_approval').all
        end

        def approval_required?(risk_tier)
          %w[high critical].include?(risk_tier.to_s)
        end

        def escalate(worker_id)
          worker = find_worker(worker_id)
          return { escalated: false, reason: 'worker not found' } unless worker
          return { escalated: false, reason: 'not pending approval' } unless worker.lifecycle_state == 'pending_approval'

          timeout = settings_timeout
          pending_seconds = worker.created_at ? (Time.now.utc - worker.created_at) : 0

          if pending_seconds >= timeout
            emit_event('worker.registration.escalated', worker_id: worker_id, pending_seconds: pending_seconds)
            log_info "worker=#{worker_id} escalated pending_seconds=#{pending_seconds.to_i}"
            { escalated: true, worker_id: worker_id, pending_seconds: pending_seconds.to_i }
          else
            remaining = (timeout - pending_seconds).to_i
            { escalated: false, reason: 'timeout not reached', remaining_seconds: remaining }
          end
        end

        private

        def find_worker(worker_id)
          return nil unless defined?(Legion::Data::Model::DigitalWorker)

          Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
        end

        def find_pending!(worker_id)
          worker = find_worker(worker_id)
          raise ArgumentError, "worker not found: #{worker_id}" unless worker

          unless worker.lifecycle_state == 'pending_approval'
            raise ArgumentError,
                  "worker #{worker_id} is not pending approval (state: #{worker.lifecycle_state})"
          end

          worker
        end

        def create_airb_intake(worker)
          return nil unless defined?(Legion::DigitalWorker::Airb)

          Legion::DigitalWorker::Airb.create_intake(
            worker.worker_id,
            description: "Registration request for #{worker.name} (risk_tier: #{worker.risk_tier})"
          )
        rescue StandardError => e
          log_debug "AIRB intake creation failed: #{e.message}"
          nil
        end

        def settings_timeout
          return APPROVAL_TIMEOUT_SECONDS unless defined?(Legion::Settings)

          Legion::Settings.dig(:digital_worker, :approval_timeout_seconds) || APPROVAL_TIMEOUT_SECONDS
        end

        def emit_event(name, **payload)
          return unless defined?(Legion::Events)

          Legion::Events.emit(name, **payload)
        rescue StandardError => e
          log_debug "event emit failed: #{e.message}"
        end

        def record_audit(event_type, worker_id, principal, detail)
          return unless defined?(Legion::Audit)

          Legion::Audit.record(
            event_type:     event_type,
            principal_id:   principal,
            principal_type: 'human',
            action:         event_type,
            resource:       worker_id,
            source:         'system',
            status:         'success',
            detail:         detail
          )
        rescue StandardError => e
          log_debug "audit record failed: #{e.message}"
        end

        def log_info(msg)
          Legion::Logging.info "[registration] #{msg}" if defined?(Legion::Logging)
        end

        def log_debug(msg)
          Legion::Logging.debug "[registration] #{msg}" if defined?(Legion::Logging)
        end
      end
    end
  end
end
