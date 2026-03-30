# frozen_string_literal: true

return unless defined?(Legion::Data)

module Legion
  module Extensions
    module Agentic
      module Consent
        module Models
          class ConsentMap < Legion::Data::Model::Base
            set_dataset :consent_maps

            STATES = %w[pending_approval approved rejected expired].freeze

            def self.pending
              where(state: 'pending_approval')
            end

            def self.for_worker(worker_id)
              where(worker_id: worker_id)
            end

            def self.pending_for_worker(worker_id)
              where(worker_id: worker_id, state: 'pending_approval')
            end

            def approve!(approver:, notes: nil)
              update(
                state:       'approved',
                resolved_by: approver,
                resolved_at: Time.now.utc,
                notes:       notes,
                updated_at:  Time.now.utc
              )
            end

            def reject!(approver:, reason: nil)
              update(
                state:       'rejected',
                resolved_by: approver,
                resolved_at: Time.now.utc,
                notes:       reason,
                updated_at:  Time.now.utc
              )
            end

            def expire!
              update(
                state:      'expired',
                updated_at: Time.now.utc
              )
            end

            def pending?
              state == 'pending_approval'
            end

            def approved?
              state == 'approved'
            end

            def rejected?
              state == 'rejected'
            end

            def expired?
              state == 'expired'
            end
          end
        end
      end
    end
  end
end
