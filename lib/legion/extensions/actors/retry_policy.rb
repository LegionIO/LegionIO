# frozen_string_literal: true

require 'legion/task_execution'

module Legion
  module Extensions
    module Actors
      module RetryPolicy
        extend Legion::TaskExecution::Helper

        RETRY_COUNT_HEADER = 'x-retry-count'

        def self.should_retry?(retry_count:, threshold:)
          retry_count < threshold
        end

        def self.extract_retry_count(headers:)
          count = (headers || {})[RETRY_COUNT_HEADER] || (headers || {})[RETRY_COUNT_HEADER.to_sym] || 0
          Integer(count).tap { |value| raise ArgumentError, 'retry count cannot be negative' if value.negative? }
        end

        def self.retry_threshold
          task_execution_settings[:retry][:max_attempts] - 1
        end

        def self.retry_delay(retry_count:)
          policy = task_execution_settings[:retry]
          [policy[:base_delay_seconds] * (2**retry_count), policy[:max_delay_seconds]].min
        end
      end
    end
  end
end
