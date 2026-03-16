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

      def active_local_ids
        return [] unless defined?(Registry)

        Registry.local_worker_ids
      end
    end
  end
end
