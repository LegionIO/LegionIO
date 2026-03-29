# frozen_string_literal: true

module Legion
  module Extensions
    module Reconciliation
      module Actors
        # Periodic reconciliation actor.
        #
        # Runs on a configurable interval (default: every 5 minutes).  On each tick
        # it invokes the DriftChecker against all registered reconciliation targets
        # (read from settings) and attempts to reconcile any open drift entries by
        # emitting reconciliation events that downstream runners can act on.
        class ReconciliationCycle < Legion::Extensions::Actors::Every
          # Default interval in seconds (5 minutes).  Override via settings:
          #   extensions.reconciliation.interval
          def every
            interval = settings_value(:interval) || 300
            interval.to_i
          end

          def action
            log.info '[ReconciliationCycle] starting reconciliation cycle' if respond_to?(:log)

            targets = load_targets
            if targets.empty?
              log.debug '[ReconciliationCycle] no reconciliation targets configured' if respond_to?(:log)
              return
            end

            resources = build_resource_snapshots(targets)
            result    = drift_checker.check_all(resources: resources)

            log.info "[ReconciliationCycle] checked=#{result[:checked]} drifted=#{result[:drifted]}" if respond_to?(:log)

            attempt_reconciliation(result[:results]) if result[:drifted].positive?

            emit_cycle_event(result)
          rescue StandardError => e
            log_error("[ReconciliationCycle] cycle failed: #{e.message}")
          end

          private

          # Load reconciliation targets from settings.
          # Expected settings shape:
          #   extensions.reconciliation.targets:
          #     - resource: "my-service"
          #       expected: { ... }
          #       severity: "medium"
          def load_targets
            return [] unless defined?(Legion::Settings)

            Array(Legion::Settings.dig(:extensions, :reconciliation, :targets))
          rescue StandardError => e
            log_error("[ReconciliationCycle] load_targets failed: #{e.message}")
            []
          end

          # Build resource snapshots by resolving the actual state for each target.
          # Subclasses or downstream runners may override actual-state resolution.
          def build_resource_snapshots(targets)
            targets.map do |target|
              resource = target[:resource] || target['resource']
              expected = target[:expected] || target['expected'] || {}
              severity = target[:severity] || target['severity'] || 'medium'
              actual   = resolve_actual_state(resource, expected)

              { resource: resource, expected: expected, actual: actual, severity: severity }
            end.compact
          end

          # Resolve the actual (live) state for a given resource.
          # Default implementation returns the expected state (no drift).
          # Override this method or provide a :state_resolver in settings to add
          # real state introspection.
          def resolve_actual_state(resource, expected)
            resolver_class = settings_value(:state_resolver)
            if resolver_class
              klass = Kernel.const_get(resolver_class)
              return klass.new.resolve(resource: resource) if klass.method_defined?(:resolve)
            end

            # Default: no drift (returns expected unchanged)
            expected
          rescue StandardError => e
            log_error("[ReconciliationCycle] resolve_actual_state failed for #{resource}: #{e.message}")
            expected
          end

          # For each drifted result, emit a reconciliation event so that
          # downstream runners can take corrective action.
          def attempt_reconciliation(results)
            results.select { |r| r[:drifted] }.each do |result|
              emit_reconciliation_event(result)
            end
          end

          def emit_reconciliation_event(result)
            return unless defined?(Legion::Events)

            Legion::Events.emit('reconciliation.reconcile_requested',
                                resource:    result[:resource],
                                drift_id:    result[:drift_id],
                                differences: result[:differences],
                                severity:    result.dig(:summary, :severity),
                                at:          Time.now.utc)
          rescue StandardError => e
            log_error("[ReconciliationCycle] emit_reconciliation_event failed: #{e.message}")
          end

          def emit_cycle_event(result)
            return unless defined?(Legion::Events)

            Legion::Events.emit('reconciliation.cycle_complete',
                                checked: result[:checked],
                                drifted: result[:drifted],
                                at:      Time.now.utc)
          rescue StandardError => e
            log_error("[ReconciliationCycle] emit_cycle_event failed: #{e.message}")
          end

          def drift_checker
            @drift_checker ||= Object.new.extend(Runners::DriftChecker)
          end

          def settings_value(key)
            Legion::Settings.dig(:extensions, :reconciliation, key)
          rescue StandardError
            nil
          end

          def log_error(msg)
            if defined?(Legion::Logging)
              Legion::Logging.error(msg)
            else
              warn(msg)
            end
          end
        end
      end
    end
  end
end
