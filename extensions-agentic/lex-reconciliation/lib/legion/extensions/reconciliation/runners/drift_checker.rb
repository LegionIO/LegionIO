# frozen_string_literal: true

module Legion
  module Extensions
    module Reconciliation
      module Runners
        # Detects drift between expected (desired) state and actual (observed) state.
        #
        # Callers supply a resource identifier, the expected state hash, and the actual
        # state hash.  The runner performs a deep comparison, records any deviations to
        # DriftLog, and returns a structured result describing what drifted.
        module DriftChecker
          # Check a single resource for drift.
          #
          # @param resource  [String] identifier for the resource being checked
          # @param expected  [Hash]   the desired / expected state
          # @param actual    [Hash]   the currently observed state
          # @param severity  [String] override severity ('low','medium','high','critical')
          # @return [Hash] { drifted: Boolean, drift_entries: Array<Hash>, summary: Hash }
          def check(resource:, expected:, actual:, severity: 'medium', **_opts)
            log.debug "[DriftChecker] checking resource: #{resource}" if respond_to?(:log)

            differences = deep_diff(expected, actual)

            if differences.empty?
              log.debug "[DriftChecker] no drift detected for #{resource}" if respond_to?(:log)
              return { drifted: false, resource: resource, drift_entries: [], summary: { total: 0 } }
            end

            log.warn "[DriftChecker] drift detected for #{resource}: #{differences.size} difference(s)" if respond_to?(:log)

            drift_entry = DriftLog.record(
              resource:      resource,
              expected:      expected,
              actual:        actual,
              drift_type:    infer_drift_type(differences),
              severity:      severity,
              reconciled_by: 'drift_checker'
            )

            {
              drifted:       true,
              resource:      resource,
              drift_id:      drift_entry&.dig(:drift_id),
              differences:   differences,
              drift_entries: drift_entry ? [drift_entry] : [],
              summary:       {
                total:    differences.size,
                severity: severity,
                paths:    differences.map { |d| d[:path] }
              }
            }
          rescue StandardError => e
            error_msg = "[DriftChecker] check failed for #{resource}: #{e.message}"
            defined?(Legion::Logging) ? Legion::Logging.error(error_msg) : warn(error_msg)
            { drifted: false, resource: resource, error: e.message, drift_entries: [], summary: { total: 0 } }
          end

          # Check multiple resources in one call.
          #
          # @param resources [Array<Hash>] each element must have :resource, :expected, :actual
          # @return [Hash] { checked: Integer, drifted: Integer, results: Array<Hash> }
          def check_all(resources:, severity: 'medium', **_opts)
            results = resources.map do |r|
              check(
                resource: r[:resource],
                expected: r[:expected],
                actual:   r[:actual],
                severity: r[:severity] || severity
              )
            end

            {
              checked: results.size,
              drifted: results.count { |r| r[:drifted] },
              results: results
            }
          rescue StandardError => e
            error_msg = "[DriftChecker] check_all failed: #{e.message}"
            defined?(Legion::Logging) ? Legion::Logging.error(error_msg) : warn(error_msg)
            { checked: 0, drifted: 0, results: [], error: e.message }
          end

          # Return a summary of current open drift entries from the log.
          #
          # @return [Hash]
          def drift_summary(**_opts)
            DriftLog.summary
          rescue StandardError => e
            error_msg = "[DriftChecker] drift_summary failed: #{e.message}"
            defined?(Legion::Logging) ? Legion::Logging.error(error_msg) : warn(error_msg)
            { open: 0, resolved: 0, by_severity: {}, error: e.message }
          end

          private

          # Perform a recursive diff between two hashes/values.
          # Returns an array of { path:, expected:, actual: } for each differing leaf.
          def deep_diff(expected, actual, path = '')
            differences = []

            case expected
            when Hash
              all_keys = (expected.keys + (actual.is_a?(Hash) ? actual.keys : [])).uniq
              all_keys.each do |key|
                child_path = path.empty? ? key.to_s : "#{path}.#{key}"
                exp_val    = expected[key]
                act_val    = actual.is_a?(Hash) ? actual[key] : nil
                differences.concat(deep_diff(exp_val, act_val, child_path))
              end
            when Array
              if !actual.is_a?(Array) || expected != actual
                differences << { path: path.empty? ? '(root)' : path, expected: expected, actual: actual }
              end
            else
              if expected != actual
                differences << { path: path.empty? ? '(root)' : path, expected: expected, actual: actual }
              end
            end

            differences
          end

          # Infer a human-readable drift type from the set of differences.
          def infer_drift_type(differences)
            paths = differences.map { |d| d[:path].to_s }
            return 'schema'  if paths.any? { |p| p.include?('schema') || p.include?('type') }
            return 'config'  if paths.any? { |p| p.include?('config') || p.include?('setting') }
            return 'version' if paths.any? { |p| p.include?('version') }

            'state'
          end
        end
      end
    end
  end
end
