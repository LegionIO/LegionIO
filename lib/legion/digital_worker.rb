# frozen_string_literal: true

require 'securerandom'

module Legion
  module DigitalWorker
    class << self
      def register(name:, extension_name:, entra_app_id:, owner_msid:, **opts)
        Legion::Data::Model::DigitalWorker.create(
          worker_id:       SecureRandom.uuid,
          name:            name,
          extension_name:  extension_name,
          entra_app_id:    entra_app_id,
          owner_msid:      owner_msid,
          owner_name:      opts[:owner_name],
          business_role:   opts[:business_role],
          risk_tier:       opts[:risk_tier],
          team:            opts[:team],
          manager_msid:    opts[:manager_msid],
          lifecycle_state: 'bootstrap',
          consent_tier:    'supervised',
          trust_score:     0.0
        )
      end

      def find(worker_id:)
        Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
      end

      def find_by_entra_app(entra_app_id:)
        Legion::Data::Model::DigitalWorker.first(entra_app_id: entra_app_id)
      end

      def active_workers
        Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'active')
      end

      def by_owner(owner_msid:)
        Legion::Data::Model::DigitalWorker.where(owner_msid: owner_msid)
      end

      def by_team(team:)
        Legion::Data::Model::DigitalWorker.where(team: team)
      end

      def heartbeat(worker_id:, health_status: 'healthy', health_node: nil)
        worker = Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
        return nil unless worker

        updates = { last_heartbeat_at: Time.now.utc, health_status: health_status }
        updates[:health_node] = health_node if health_node
        worker.update(updates)
        worker
      end

      def detect_orphans(stale_days: 7)
        cutoff = Time.now.utc - (stale_days * 86_400)
        active = Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'active')
        active.all.select do |w|
          w.last_heartbeat_at.nil? || w.last_heartbeat_at < cutoff
        end
      end

      def pause_orphans!(stale_days: 7, by: 'system:orphan_detection')
        orphans = detect_orphans(stale_days: stale_days)
        orphans.each do |worker|
          Lifecycle.transition!(
            worker,
            to_state:           'paused',
            by:                 by,
            reason:             "no heartbeat for #{stale_days}+ days",
            authority_verified: true
          )
          if defined?(Legion::Events)
            Legion::Events.emit('worker.orphan_detected', {
                                  worker_id:         worker.worker_id,
                                  owner_msid:        worker.owner_msid,
                                  last_heartbeat_at: worker.last_heartbeat_at,
                                  at:                Time.now.utc
                                })
          end
        rescue Lifecycle::InvalidTransition => e
          Legion::Logging.debug("[OrphanDetection] skip #{worker.worker_id}: #{e.message}") if defined?(Legion::Logging)
        end
        orphans
      end

      def active_local_ids
        return [] unless defined?(Registry)

        Registry.local_worker_ids
      end
    end
  end
end
