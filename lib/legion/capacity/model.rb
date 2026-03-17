# frozen_string_literal: true

module Legion
  module Capacity
    class Model
      DEFAULTS = {
        tasks_per_second:   10,
        utilization_target: 0.7,
        availability_hours: 24,
        overhead_factor:    0.15
      }.freeze

      def initialize(workers:, config: {})
        @workers = Array(workers)
        @config = DEFAULTS.merge(config)
      end

      def aggregate
        active = @workers.select { |w| active_worker?(w) }
        tps = @config[:tasks_per_second]
        {
          total_workers:            @workers.size,
          active_workers:           active.size,
          max_throughput_tps:       active.size * tps,
          effective_throughput_tps: (active.size * tps * @config[:utilization_target]).round,
          utilization_target:       @config[:utilization_target],
          availability_hours:       @config[:availability_hours]
        }
      end

      def forecast(days: 30, growth_rate: 0.0)
        current = aggregate
        projected = (current[:active_workers] * (1 + (growth_rate * days / 30.0))).ceil
        tps = @config[:tasks_per_second]
        {
          period_days:             days,
          growth_rate:             growth_rate,
          current_workers:         current[:active_workers],
          projected_workers:       projected,
          projected_max_tps:       projected * tps,
          projected_effective_tps: (projected * tps * @config[:utilization_target]).round
        }
      end

      def per_worker_stats
        @workers.map do |w|
          id = w[:worker_id] || w[:id] || 'unknown'
          {
            worker_id:    id,
            status:       w[:status] || w[:lifecycle_state] || 'unknown',
            capacity_tps: active_worker?(w) ? @config[:tasks_per_second] : 0
          }
        end
      end

      private

      def active_worker?(worker)
        status = (worker[:status] || worker[:lifecycle_state]).to_s
        %w[active running].include?(status)
      end
    end
  end
end
