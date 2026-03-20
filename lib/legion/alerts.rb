# frozen_string_literal: true

module Legion
  module Alerts
    AlertRule = Struct.new(:name, :event_pattern, :condition, :severity, :channels, :cooldown_seconds)

    DEFAULT_RULES = [
      { name: 'consent_violation', event_pattern: 'governance.consent_violation', severity: 'critical',
        channels: %w[events log], cooldown_seconds: 300 },
      { name: 'extinction_trigger', event_pattern: 'extinction.*', severity: 'critical',
        channels: %w[events log], cooldown_seconds: 0 },
      { name: 'error_spike', event_pattern: 'runner.failure',
        condition: { count_threshold: 10, window_seconds: 60 }, severity: 'warning',
        channels: %w[events log], cooldown_seconds: 300 },
      { name: 'budget_exceeded', event_pattern: 'finops.budget_exceeded', severity: 'warning',
        channels: %w[events log], cooldown_seconds: 3600 },
      { name: 'safety_action_burst', event_pattern: 'ingress.received',
        condition: { count_threshold: 100, window_seconds: 60 }, severity: 'warning',
        channels: %w[events log], cooldown_seconds: 300 },
      { name: 'safety_scope_escalation_spike', event_pattern: 'rbac.deny',
        condition: { count_threshold: 5, window_seconds: 300 }, severity: 'critical',
        channels: %w[events log], cooldown_seconds: 300 },
      { name: 'safety_probe_detected', event_pattern: 'privatecore.probe_detected', severity: 'critical',
        channels: %w[events log], cooldown_seconds: 0 },
      { name: 'safety_confidence_collapse', event_pattern: 'synapse.confidence_update',
        condition: { count_threshold: 3, window_seconds: 300 }, severity: 'warning',
        channels: %w[events log], cooldown_seconds: 300 }
    ].freeze

    class Engine
      attr_reader :rules

      def initialize(rules: [])
        @rules = rules.map { |r| r.is_a?(AlertRule) ? r : AlertRule.new(**r.transform_keys(&:to_sym)) }
        @counters = {}
        @last_fired = {}
      end

      def evaluate(event_name, payload = {})
        fired = []
        @rules.each do |rule|
          next unless event_matches?(event_name, rule.event_pattern)
          next unless condition_met?(rule, event_name)
          next if in_cooldown?(rule)

          fire_alert(rule, event_name, payload)
          fired << rule.name
        end
        fired
      end

      private

      def event_matches?(name, pattern)
        File.fnmatch?(pattern, name)
      end

      def condition_met?(rule, event_name)
        cond = rule.condition
        return true unless cond.is_a?(Hash)

        key = "#{rule.name}:#{event_name}"
        @counters[key] ||= { count: 0, window_start: Time.now }

        window = cond[:window_seconds] || 60
        @counters[key] = { count: 0, window_start: Time.now } if Time.now - @counters[key][:window_start] > window

        @counters[key][:count] += 1
        @counters[key][:count] >= (cond[:count_threshold] || 1)
      end

      def in_cooldown?(rule)
        last = @last_fired[rule.name]
        return false unless last

        Time.now - last < (rule.cooldown_seconds || 0)
      end

      def fire_alert(rule, event_name, payload)
        @last_fired[rule.name] = Time.now
        alert = { rule: rule.name, event: event_name, severity: rule.severity,
                  payload: payload, fired_at: Time.now.utc }

        (rule.channels || []).each do |channel|
          case channel.to_sym
          when :events
            Legion::Events.emit('alert.fired', alert) if defined?(Legion::Events)
          when :log
            Legion::Logging.warn "[alert] #{rule.name}: #{event_name} (#{rule.severity})" if defined?(Legion::Logging)
          when :webhook
            Legion::Webhooks.dispatch('alert.fired', alert) if defined?(Legion::Webhooks)
          end
        end
      end
    end

    class << self
      def setup
        rules = load_rules
        @engine = Engine.new(rules: rules)
        register_listener
        Legion::Logging.debug "Alerts: #{rules.size} rules loaded" if defined?(Legion::Logging)
      end

      attr_reader :engine

      def reset!
        @engine = nil
      end

      private

      def load_rules
        custom = begin
          Legion::Settings[:alerts][:rules]
        rescue StandardError
          nil
        end
        custom && !custom.empty? ? custom : DEFAULT_RULES
      end

      def register_listener
        return unless defined?(Legion::Events)

        Legion::Events.on('*') do |event_name, **payload|
          @engine&.evaluate(event_name, payload)
        end
      end
    end
  end
end
