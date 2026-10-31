# frozen_string_literal: true

require 'legion/settings'

module Legion
  module TaskExecution
    module Settings
      def self.default
        {
          retry:     { max_attempts: 3, base_delay_seconds: 1, max_delay_seconds: 30, safe_runners: {} },
          execution: { max_payload_bytes: 524_288 },
          ingress:   { trusted_internal_principal: { id: 'legion-task-service', type: 'worker', roles: { worker: true } } }
        }
      end
    end

    module Helper
      def task_execution_settings
        unless Legion::Settings.loader&.merged_modules&.key?(:task_execution)
          Legion::Settings.register_library(:task_execution, Legion::TaskExecution::Settings.default)
        end
        policy = Legion::Settings[:task_execution]
        raise ArgumentError, 'task_execution must be a Hash' unless policy.is_a?(Hash)

        %i[retry execution ingress].each do |section|
          raise ArgumentError, "task_execution.#{section} must be a Hash" unless policy[section].is_a?(Hash)
        end
        retry_policy = policy[:retry]
        { max_attempts: retry_policy[:max_attempts], base_delay_seconds: retry_policy[:base_delay_seconds],
          max_delay_seconds: retry_policy[:max_delay_seconds], max_payload_bytes: policy[:execution][:max_payload_bytes] }.each do |key, value|
          raise ArgumentError, "task_execution.#{key} must be a positive Integer" unless value.is_a?(Integer) && value.positive?
        end
        if retry_policy[:max_delay_seconds] < retry_policy[:base_delay_seconds]
          raise ArgumentError, 'task_execution retry maximum delay must not be below base delay'
        end

        service = policy[:ingress][:trusted_internal_principal]
        unless service.is_a?(Hash) && %i[id type].all? { |key| service[key].is_a?(String) && !service[key].strip.empty? }
          raise ArgumentError, 'task_execution trusted internal principal requires nonempty id and type'
        end

        { safe_runners: retry_policy[:safe_runners], roles: service[:roles] }.each do |name, grants|
          valid = grants.is_a?(Hash) && grants.keys.map(&:to_s).uniq.size == grants.size
          valid &&= grants.all? do |key, enabled|
            (key.is_a?(String) || key.is_a?(Symbol)) && !key.to_s.empty? && [true, false].include?(enabled)
          end
          raise ArgumentError, "task_execution.#{name} must be a Boolean permission map" unless valid
        end
        policy
      end
    end
  end
end

Legion::Settings.register_library(:task_execution, Legion::TaskExecution::Settings.default)
