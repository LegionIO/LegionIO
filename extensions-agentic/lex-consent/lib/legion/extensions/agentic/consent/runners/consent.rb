# frozen_string_literal: true

module Legion
  module Extensions
    module Agentic
      module Consent
        module Runners
          module Consent
            # Request human approval for a worker's autonomous tier promotion.
            # Creates a ConsentMap record in pending_approval state.
            #
            # @param worker_id [String] the worker requesting promotion
            # @param from_tier [String] current consent tier
            # @param to_tier [String] requested consent tier
            # @param requested_by [String] identity requesting the promotion
            # @param context [Hash] optional metadata about why promotion is requested
            # @return [Hash]
            def request_promotion(worker_id:, from_tier:, to_tier:, requested_by: 'system', context: {}, **)
              unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)
                return { success: false, reason: :model_unavailable }
              end

              existing = Legion::Extensions::Agentic::Consent::Models::ConsentMap
                         .pending_for_worker(worker_id).first

              if existing
                Legion::Logging.info "[lex-consent] promotion already pending for worker=#{worker_id}" if defined?(Legion::Logging)
                return { success: false, reason: :already_pending, consent_map_id: existing.id }
              end

              record = Legion::Extensions::Agentic::Consent::Models::ConsentMap.create(
                worker_id:    worker_id,
                from_tier:    from_tier,
                to_tier:      to_tier,
                requested_by: requested_by,
                state:        'pending_approval',
                context:      defined?(Legion::JSON) ? Legion::JSON.dump(context) : context.to_json,
                created_at:   Time.now.utc,
                updated_at:   Time.now.utc
              )

              Legion::Events.emit('consent.promotion_requested', {
                                    worker_id:      worker_id,
                                    from_tier:      from_tier,
                                    to_tier:        to_tier,
                                    requested_by:   requested_by,
                                    consent_map_id: record.id,
                                    at:             Time.now.utc
                                  }) if defined?(Legion::Events)

              Legion::Logging.info "[lex-consent] promotion requested worker=#{worker_id} #{from_tier}->#{to_tier} id=#{record.id}" if defined?(Legion::Logging)

              { success: true, consent_map_id: record.id, state: 'pending_approval' }
            rescue StandardError => e
              Legion::Logging.error "[lex-consent] request_promotion failed: #{e.message}" if defined?(Legion::Logging)
              { success: false, reason: e.message }
            end

            # Approve a pending tier promotion request.
            #
            # @param consent_map_id [Integer] the ConsentMap record to approve
            # @param approver [String] identity of the approver
            # @param notes [String] optional approval notes
            # @return [Hash]
            def approve_promotion(consent_map_id:, approver:, notes: nil, **)
              unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)
                return { success: false, reason: :model_unavailable }
              end

              record = Legion::Extensions::Agentic::Consent::Models::ConsentMap[consent_map_id.to_i]
              return { success: false, reason: :not_found } unless record
              return { success: false, reason: :not_pending, state: record.state } unless record.pending?

              record.approve!(approver: approver, notes: notes)

              apply_promotion(record)

              Legion::Events.emit('consent.promotion_approved', {
                                    consent_map_id: record.id,
                                    worker_id:      record.worker_id,
                                    from_tier:      record.from_tier,
                                    to_tier:        record.to_tier,
                                    approver:       approver,
                                    at:             Time.now.utc
                                  }) if defined?(Legion::Events)

              Legion::Logging.info "[lex-consent] approved consent_map_id=#{record.id} worker=#{record.worker_id} by=#{approver}" if defined?(Legion::Logging)

              { success: true, consent_map_id: record.id, worker_id: record.worker_id, state: 'approved', to_tier: record.to_tier }
            rescue StandardError => e
              Legion::Logging.error "[lex-consent] approve_promotion failed: #{e.message}" if defined?(Legion::Logging)
              { success: false, reason: e.message }
            end

            # Reject a pending tier promotion request.
            #
            # @param consent_map_id [Integer] the ConsentMap record to reject
            # @param approver [String] identity of the approver
            # @param reason [String] rejection reason (required)
            # @return [Hash]
            def reject_promotion(consent_map_id:, approver:, reason:, **)
              unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)
                return { success: false, reason: :model_unavailable }
              end

              return { success: false, reason: :missing_reason } if reason.nil? || reason.to_s.strip.empty?

              record = Legion::Extensions::Agentic::Consent::Models::ConsentMap[consent_map_id.to_i]
              return { success: false, reason: :not_found } unless record
              return { success: false, reason: :not_pending, state: record.state } unless record.pending?

              record.reject!(approver: approver, reason: reason)

              Legion::Events.emit('consent.promotion_rejected', {
                                    consent_map_id: record.id,
                                    worker_id:      record.worker_id,
                                    from_tier:      record.from_tier,
                                    to_tier:        record.to_tier,
                                    approver:       approver,
                                    reason:         reason,
                                    at:             Time.now.utc
                                  }) if defined?(Legion::Events)

              Legion::Logging.info "[lex-consent] rejected consent_map_id=#{record.id} worker=#{record.worker_id} by=#{approver}" if defined?(Legion::Logging)

              { success: true, consent_map_id: record.id, worker_id: record.worker_id, state: 'rejected' }
            rescue StandardError => e
              Legion::Logging.error "[lex-consent] reject_promotion failed: #{e.message}" if defined?(Legion::Logging)
              { success: false, reason: e.message }
            end

            # Expire all pending promotion requests older than ttl_hours.
            # Intended to be run on a schedule (e.g. every hour).
            #
            # @param ttl_hours [Integer] how many hours before a pending request expires (default 72)
            # @return [Hash]
            def expire_pending_approvals(ttl_hours: 72, **)
              unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)
                return { success: false, reason: :model_unavailable }
              end

              cutoff = Time.now.utc - (ttl_hours * 3600)
              expired_count = 0

              Legion::Extensions::Agentic::Consent::Models::ConsentMap
                .pending
                .where { created_at < cutoff }
                .each do |record|
                  record.expire!
                  expired_count += 1

                  Legion::Events.emit('consent.promotion_expired', {
                                        consent_map_id: record.id,
                                        worker_id:      record.worker_id,
                                        from_tier:      record.from_tier,
                                        to_tier:        record.to_tier,
                                        at:             Time.now.utc
                                      }) if defined?(Legion::Events)
                rescue StandardError => e
                  Legion::Logging.warn "[lex-consent] expire failed for id=#{record.id}: #{e.message}" if defined?(Legion::Logging)
                end

              Legion::Logging.info "[lex-consent] expired #{expired_count} pending approvals (ttl=#{ttl_hours}h)" if defined?(Legion::Logging)

              { success: true, expired: expired_count, ttl_hours: ttl_hours }
            rescue StandardError => e
              Legion::Logging.error "[lex-consent] expire_pending_approvals failed: #{e.message}" if defined?(Legion::Logging)
              { success: false, reason: e.message }
            end

            # List pending promotion requests.
            #
            # @param worker_id [String] optional filter by worker
            # @return [Hash]
            def list_pending(worker_id: nil, **)
              unless defined?(Legion::Extensions::Agentic::Consent::Models::ConsentMap)
                return { success: false, reason: :model_unavailable }
              end

              ds = Legion::Extensions::Agentic::Consent::Models::ConsentMap.pending
              ds = ds.where(worker_id: worker_id) if worker_id
              records = ds.all

              { success: true, count: records.size, pending: records.map(&:values) }
            rescue StandardError => e
              Legion::Logging.error "[lex-consent] list_pending failed: #{e.message}" if defined?(Legion::Logging)
              { success: false, reason: e.message }
            end

            private

            def apply_promotion(record)
              return unless defined?(Legion::Data::Model::DigitalWorker)

              worker = Legion::Data::Model::DigitalWorker.first(worker_id: record.worker_id)
              return unless worker

              worker.update(consent_tier: record.to_tier, updated_at: Time.now.utc)

              Legion::Logging.info "[lex-consent] applied tier promotion worker=#{record.worker_id} tier=#{record.to_tier}" if defined?(Legion::Logging)
            rescue StandardError => e
              Legion::Logging.warn "[lex-consent] apply_promotion failed for worker=#{record.worker_id}: #{e.message}" if defined?(Legion::Logging)
            end
          end
        end
      end
    end
  end
end
