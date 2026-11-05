# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module RetryPolicy
        RETRY_COUNT_HEADER = 'x-retry-count'

        def self.should_retry?(retry_count:, threshold:)
          retry_count < threshold
        end

        def self.extract_retry_count(headers:)
          count = (headers || {})[RETRY_COUNT_HEADER] || (headers || {})[RETRY_COUNT_HEADER.to_sym] || 0
          Integer(count).tap { |value| raise ArgumentError, 'retry count cannot be negative' if value.negative? }
        end

        def self.retry_threshold
          2
        end

        def self.retry_delay(retry_count:)
          [2**retry_count, 30].min
        end
      end
    end
  end
end
