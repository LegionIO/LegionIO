# frozen_string_literal: true

module Legion
  module Telemetry
    class SlidingWindow
      def initialize(window_seconds)
        @window = window_seconds
        @entries = []
        @mutex = Mutex.new
      end

      def push(**entry)
        @mutex.synchronize do
          @entries << entry.merge(at: Time.now)
          prune!
        end
      end

      def count
        @mutex.synchronize do
          prune!
          @entries.size
        end
      end

      def count_for(**filters)
        @mutex.synchronize do
          prune!
          @entries.count { |e| filters.all? { |k, v| e[k] == v } }
        end
      end

      def entries_matching(**filters)
        @mutex.synchronize do
          prune!
          @entries.select { |e| filters.all? { |k, v| e[k] == v } }
        end
      end

      private

      def prune!
        cutoff = Time.now - @window
        @entries.reject! { |e| e[:at] < cutoff }
      end
    end

    module SafetyMetrics
      WINDOWS = {
        actions:    60,
        failures:   300,
        successes:  300,
        confidence: 300
      }.freeze

      module_function

      def start
        return unless safety_enabled?

        init_windows
        register_prometheus_metrics
        subscribe_events
      end

      def init_windows
        @windows = WINDOWS.transform_values { |secs| SlidingWindow.new(secs) }
      end

      def subscribe_events
        return unless defined?(Legion::Events)

        Legion::Events.on('ingress.received') { |e| record_action(**e) }
        Legion::Events.on('runner.failure')               { |e| record_failure(**e) }
        Legion::Events.on('runner.success')               { |e| record_success(**e) }
        Legion::Events.on('rbac.deny')                    { |e| record_escalation(**e) }
        Legion::Events.on('governance.consent_violation') { |e| record_governance(**e) }
        Legion::Events.on('privatecore.probe_detected')   { |e| record_probe(**e) }
        Legion::Events.on('synapse.confidence_update')    { |e| record_confidence(**e) }
      end

      def record_action(agent_id: 'unknown', **)
        @windows[:actions]&.push(agent: agent_id)
      end

      def record_failure(agent_id: 'unknown', **)
        @windows[:failures]&.push(agent: agent_id, type: :failure)
      end

      def record_success(agent_id: 'unknown', **)
        @windows[:successes]&.push(agent: agent_id, type: :success)
      end

      def record_escalation(agent_id: 'unknown', **) # rubocop:disable Lint/UnusedMethodArgument
        @escalation_count = (@escalation_count || 0) + 1
      end

      def record_governance(**)
        @governance_count = (@governance_count || 0) + 1
      end

      def record_probe(**)
        @probe_count = (@probe_count || 0) + 1
      end

      def record_confidence(agent_id: 'unknown', delta: 0.0, **)
        @windows[:confidence]&.push(agent: agent_id, delta: delta)
      end

      def actions_per_minute(agent_id)
        @windows[:actions]&.count_for(agent: agent_id) || 0
      end

      def tool_failure_ratio(agent_id)
        fails = @windows[:failures]&.count_for(agent: agent_id) || 0
        successes = @windows[:successes]&.count_for(agent: agent_id) || 0
        total = fails + successes
        total.zero? ? 0.0 : fails.to_f / total
      end

      def confidence_drift(agent_id)
        entries = @windows[:confidence]&.entries_matching(agent: agent_id) || []
        return 0.0 if entries.empty?

        entries.sum { |e| e[:delta] || 0.0 } / entries.size
      end

      def scope_escalation_total
        @escalation_count || 0
      end

      def governance_override_total
        @governance_count || 0
      end

      def probe_detection_total
        @probe_count || 0
      end

      def safety_enabled?
        Legion::Settings.dig(:telemetry, :safety, :enabled)
      rescue StandardError
        false
      end

      def register_prometheus_metrics
        return unless defined?(Legion::Metrics) && Legion::Metrics.respond_to?(:register_gauge)

        Legion::Metrics.register_gauge(:legion_safety_actions_per_minute,
                                       'Runner invocations per agent per minute')
        Legion::Metrics.register_gauge(:legion_safety_tool_failure_ratio,
                                       'Tool failure percentage over 5m window')
        Legion::Metrics.register_gauge(:legion_safety_confidence_drift,
                                       'Rate of confidence decrease across synapses')
        Legion::Metrics.register_counter(:legion_safety_scope_escalation_total,
                                         'Denied access attempts')
        Legion::Metrics.register_counter(:legion_safety_governance_override_total,
                                         'Governance constraint violations')
        Legion::Metrics.register_counter(:legion_safety_probe_detection_total,
                                         'Detected prompt injection probes')
      rescue StandardError
        nil
      end
    end
  end
end
