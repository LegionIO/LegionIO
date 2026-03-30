# frozen_string_literal: true

module Legion
  module Extensions
    module Reconciliation
      # Persistent drift event log.
      # Records each detected drift event with resource identity, expected state,
      # actual state, severity, and resolution status.
      module DriftLog
        SEVERITY_LEVELS = %w[low medium high critical].freeze
        STATUS_VALUES   = %w[open resolved ignored].freeze

        class << self
          # Record a new drift event.
          #
          # @param resource      [String] identifier of the drifted resource
          # @param expected      [Hash]   the expected (desired) state
          # @param actual        [Hash]   the observed (actual) state
          # @param drift_type    [String] category of drift (e.g. 'config', 'state', 'schema')
          # @param severity      [String] one of SEVERITY_LEVELS
          # @param reconciled_by [String] runner or actor that detected the drift
          # @return [Hash] the recorded drift entry
          def record(resource:, expected:, actual:, **opts)
            entry = build_entry(
              resource:      resource,
              expected:      expected,
              actual:        actual,
              drift_type:    opts.fetch(:drift_type, 'state'),
              severity:      opts.fetch(:severity, 'medium'),
              reconciled_by: opts.fetch(:reconciled_by, 'drift_checker')
            )

            persist(entry)
            emit_event(entry)
            entry
          rescue StandardError => e
            Legion::Logging.error "[DriftLog] record failed for #{resource}: #{e.message}" if defined?(Legion::Logging)
            nil
          end

          # Mark a drift entry as resolved.
          #
          # @param drift_id  [String] the drift entry identifier
          # @param resolved_by [String] actor or runner that performed reconciliation
          # @return [Boolean] true if updated, false if not found
          def resolve(drift_id:, resolved_by: 'reconciliation_cycle')
            return false unless data_available?

            count = Legion::Data.connection[:reconciliation_drift_log]
                                .where(drift_id: drift_id, status: 'open')
                                .update(
                                  status:      'resolved',
                                  resolved_by: resolved_by,
                                  resolved_at: Time.now.utc
                                )
            count.positive?
          rescue StandardError => e
            Legion::Logging.error "[DriftLog] resolve failed for #{drift_id}: #{e.message}" if defined?(Legion::Logging)
            false
          end

          # Query open drift entries, optionally filtered by resource or severity.
          #
          # @param resource  [String, nil] filter by resource identifier
          # @param severity  [String, nil] filter by severity level
          # @param limit     [Integer]     maximum number of entries to return
          # @return [Array<Hash>]
          def open_entries(resource: nil, severity: nil, limit: 100)
            return [] unless data_available?

            ds = Legion::Data.connection[:reconciliation_drift_log].where(status: 'open')
            ds = ds.where(resource: resource)   if resource
            ds = ds.where(severity: severity)   if severity
            ds.order(Sequel.desc(:detected_at)).limit(limit).all
          rescue StandardError => e
            Legion::Logging.error "[DriftLog] open_entries query failed: #{e.message}" if defined?(Legion::Logging)
            []
          end

          # Return a summary count of drift entries grouped by severity and status.
          #
          # @return [Hash]
          def summary
            return { open: 0, resolved: 0, by_severity: {} } unless data_available?

            rows = Legion::Data.connection[:reconciliation_drift_log]
                               .group_and_count(:status, :severity)
                               .all

            result = { open: 0, resolved: 0, by_severity: {} }
            rows.each do |row|
              result[:open]      += row[:count] if row[:status] == 'open'
              result[:resolved]  += row[:count] if row[:status] == 'resolved'
              sev = row[:severity].to_s
              result[:by_severity][sev] ||= { open: 0, resolved: 0 }
              result[:by_severity][sev][row[:status].to_sym] += row[:count]
            end
            result
          rescue StandardError => e
            Legion::Logging.error "[DriftLog] summary failed: #{e.message}" if defined?(Legion::Logging)
            { open: 0, resolved: 0, by_severity: {} }
          end

          private

          def build_entry(resource:, expected:, actual:, drift_type:, severity:, reconciled_by:) # rubocop:disable Metrics/ParameterLists
            require 'securerandom'
            {
              drift_id:    SecureRandom.uuid,
              resource:    resource.to_s,
              expected:    safe_serialize(expected),
              actual:      safe_serialize(actual),
              drift_type:  drift_type.to_s,
              severity:    SEVERITY_LEVELS.include?(severity.to_s) ? severity.to_s : 'medium',
              status:      'open',
              detected_by: reconciled_by.to_s,
              detected_at: Time.now.utc,
              resolved_by: nil,
              resolved_at: nil
            }
          end

          def persist(entry)
            return unless data_available?

            Legion::Data.connection[:reconciliation_drift_log].insert(entry)
          rescue Sequel::Error => e
            Legion::Logging.warn "[DriftLog] persist failed (table may not exist): #{e.message}" if defined?(Legion::Logging)
          end

          def emit_event(entry)
            return unless defined?(Legion::Events)

            Legion::Events.emit('reconciliation.drift_detected',
                                drift_id:   entry[:drift_id],
                                resource:   entry[:resource],
                                drift_type: entry[:drift_type],
                                severity:   entry[:severity],
                                at:         entry[:detected_at])
          rescue StandardError => e
            Legion::Logging.warn "[DriftLog] event emit failed: #{e.message}" if defined?(Legion::Logging)
          end

          def data_available?
            defined?(Legion::Data) &&
              Legion::Data.respond_to?(:connection) &&
              !Legion::Data.connection.nil?
          end

          def safe_serialize(obj)
            return obj.to_s unless defined?(Legion::JSON)

            Legion::JSON.dump(obj)
          rescue StandardError
            obj.to_s
          end
        end
      end
    end
  end
end
