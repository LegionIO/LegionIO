# frozen_string_literal: true

module Legion
  module Metrics
    class << self
      def available?
        defined?(Prometheus::Client) ? true : false
      end

      def setup
        return unless available?

        init_registry
        init_metrics
        register_event_listeners
      end

      attr_reader :registry

      def render
        return '' unless available?

        Prometheus::Client::Formats::Text.marshal(@registry)
      end

      def refresh_gauges
        return unless available?

        @metrics[:uptime].set(::Process.clock_gettime(::Process::CLOCK_MONOTONIC))
        refresh_active_workers
        refresh_rolling_window
      end

      def reset!
        @registry = nil
        @metrics  = nil
        @listeners&.each { |name, block| Legion::Events.off(name, block) if defined?(Legion::Events) }
        @listeners = {}
      end

      private

      def init_registry
        @registry = Prometheus::Client::Registry.new
        @metrics  = {}
      end

      def init_metrics
        @metrics[:uptime] = @registry.gauge(:legion_uptime_seconds, docstring: 'Process uptime')
        @metrics[:active_workers] = @registry.gauge(:legion_active_workers,
                                                    docstring: 'Active workers', labels: [:lifecycle_state])
        @metrics[:tasks_total] = @registry.counter(:legion_tasks_total,
                                                   docstring: 'Total tasks', labels: [:status])
        @metrics[:tasks_per_second] = @registry.gauge(:legion_tasks_per_second, docstring: 'Task throughput')
        @metrics[:error_rate] = @registry.gauge(:legion_error_rate, docstring: 'Error rate')
        @metrics[:consent_violations] = @registry.counter(:legion_consent_violations_total,
                                                          docstring: 'Consent violations')
        @metrics[:llm_requests] = @registry.counter(:legion_llm_requests_total,
                                                    docstring: 'LLM calls', labels: %i[provider model])
        @metrics[:llm_tokens] = @registry.counter(:legion_llm_tokens_total,
                                                  docstring: 'LLM tokens', labels: %i[provider model type])
        @window = Concurrent::Array.new
      end

      def register_event_listeners
        @listeners = {}

        @listeners['ingress.received'] = Legion::Events.on('ingress.received') do |_|
          @metrics[:tasks_total].increment(labels: { status: 'queued' })
          @window << { time: Time.now, error: false }
        end

        @listeners['runner.success'] = Legion::Events.on('runner.success') do |_|
          @metrics[:tasks_total].increment(labels: { status: 'success' })
        end

        @listeners['runner.failure'] = Legion::Events.on('runner.failure') do |_|
          @metrics[:tasks_total].increment(labels: { status: 'failure' })
          @window << { time: Time.now, error: true }
        end

        @listeners['governance.consent_violation'] = Legion::Events.on('governance.consent_violation') do |_|
          @metrics[:consent_violations].increment
        end

        @listeners['metering.recorded'] = Legion::Events.on('metering.recorded') do |event|
          provider = event[:provider].to_s
          model = event[:model].to_s
          @metrics[:llm_requests].increment(labels: { provider: provider, model: model })
          @metrics[:llm_tokens].increment(labels: { provider: provider, model: model, type: 'input' },
                                          by:     event[:input_tokens].to_i)
          @metrics[:llm_tokens].increment(labels: { provider: provider, model: model, type: 'output' },
                                          by:     event[:output_tokens].to_i)
        end
      end

      def refresh_active_workers
        return unless defined?(Legion::Data::Model::DigitalWorker)

        Legion::Data::Model::DigitalWorker
          .group_and_count(:lifecycle_state)
          .each { |row| @metrics[:active_workers].set(row[:count], labels: { lifecycle_state: row[:lifecycle_state] }) }
      rescue StandardError => e
        Legion::Logging.debug "Metrics#refresh_active_workers failed: #{e.message}" if defined?(Legion::Logging)
        nil
      end

      def refresh_rolling_window
        cutoff = Time.now - 60
        @window.reject! { |e| e[:time] < cutoff }
        total = @window.size
        errors = @window.count { |e| e[:error] }
        @metrics[:tasks_per_second].set(total.to_f / 60.0)
        @metrics[:error_rate].set(total.positive? ? errors.to_f / total : 0.0)
      end
    end
  end
end
