# frozen_string_literal: true

require 'legion/settings/task_execution'

module Legion
  module TaskOutcomeObserver
    extend Legion::Settings::TaskExecution::Helper

    class << self
      def setup
        return unless enabled?

        Legion::Events.on(task_status(name: :completed)) do |payload|
          handle_outcome(payload, success: true)
        end

        Legion::Events.on(task_status(name: :failed)) do |payload|
          handle_outcome(payload, success: false)
        end

        setup_llm_reflection_hook
        Legion::Logging.info '[TaskOutcomeObserver] wired to task.completed and task.failed'
      rescue StandardError => e
        Legion::Logging.warn "[TaskOutcomeObserver] setup failed: #{e.message}" if defined?(Legion::Logging)
      end

      def enabled?
        settings = Legion::Settings[:task_outcome_observer]
        return true unless settings.is_a?(Hash)

        settings.fetch(:enabled, true)
      end

      private

      def handle_outcome(payload, success:)
        return unless observable_outcome?(payload)

        status = outcome_value(payload, :status)
        if success
          return unless outcome_value(payload, :success) == true && status == task_status(name: :completed)
        else
          return unless outcome_value(payload, :success) == false
          return unless %i[failed exception].any? { |name| status == task_status(name: name) }
        end

        runner_class = outcome_value(payload, :runner_class).to_s
        function = outcome_value(payload, :function).to_s
        domain = derive_domain(runner_class)

        record_learning(domain: domain, success: success)
        publish_lesson(runner: runner_class, function: function, success: success)
      rescue StandardError => e
        Legion::Logging.warn "[TaskOutcomeObserver] handle_outcome error: #{e.class}: #{e.message}" if defined?(Legion::Logging)
      end

      def derive_domain(runner_class)
        parts = runner_class.split('::')
        last = parts.last
        return 'unknown' unless last

        last.gsub(/([A-Z])/, '_\1').delete_prefix('_').downcase
      end

      def observable_outcome?(payload)
        outcome_value(payload, :persisted) == true &&
          !outcome_value(payload, :task_id).to_s.strip.empty? &&
          !outcome_value(payload, :runner_class).to_s.strip.empty? &&
          !outcome_value(payload, :function).to_s.strip.empty?
      end

      def outcome_value(payload, key)
        return unless payload.respond_to?(:[])

        payload.key?(key) ? payload[key] : payload[key.to_s]
      end

      def record_learning(domain:, success:)
        client = meta_learning_client
        return unless client

        domain_id = resolve_learning_domain_id(client, domain)
        return unless domain_id

        client.record_learning_episode(domain_id: domain_id, success: success)
      rescue StandardError => e
        Legion::Logging.warn "[TaskOutcomeObserver] record_learning failed: #{e.class}: #{e.message}" if defined?(Legion::Logging)
      end

      def publish_lesson(runner:, function:, success:, **_opts)
        return unless defined?(Legion::Apollo) && Legion::Apollo.respond_to?(:ingest)

        outcome = success ? 'succeeded' : 'failed'
        domain = derive_domain(runner)

        Legion::Apollo.ingest(
          content:          "task #{runner}##{function} #{outcome}",
          tags:             ['task_outcome', outcome, domain],
          knowledge_domain: 'operational',
          source_agent:     'system:task_observer',
          is_inference:     false
        )
      rescue StandardError => e
        Legion::Logging.warn "[TaskOutcomeObserver] publish_lesson failed: #{e.class}: #{e.message}" if defined?(Legion::Logging)
      end

      def setup_llm_reflection_hook
        return unless defined?(Legion::LLM)

        reflection_enabled = Legion::Settings.dig(:llm, :reflection, :enabled)
        return unless reflection_enabled

        return unless defined?(Legion::LLM::Hooks::Reflection)

        Legion::LLM::Hooks::Reflection.install
        Legion::Logging.info '[TaskOutcomeObserver] LLM reflection hook auto-installed'
      rescue StandardError => e
        Legion::Logging.warn "[TaskOutcomeObserver] LLM reflection hook install failed: #{e.class}: #{e.message}" if defined?(Legion::Logging)
      end

      def meta_learning_client
        return unless defined?(Legion::Extensions::Agentic::Learning::MetaLearning::Client)

        @meta_learning_client ||= Legion::Extensions::Agentic::Learning::MetaLearning::Client.new
      end

      def resolve_learning_domain_id(client, domain)
        domain_map = learning_domain_map
        return domain_map[domain] if domain_map.key?(domain)

        result = client.create_learning_domain(name: domain)
        return if result.is_a?(Hash) && result[:error]

        domain_id = result[:id]
        domain_map[domain] = domain_id if domain_id
        domain_id
      end

      def learning_domain_map
        @learning_domain_map ||= {}
      end
    end
  end
end
