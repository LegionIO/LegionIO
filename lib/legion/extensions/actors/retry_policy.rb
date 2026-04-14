# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module RetryPolicy
        DEFAULT_THRESHOLD = 2
        RETRY_COUNT_HEADER = 'x-retry-count'

        module_function

        def should_retry?(retry_count:, threshold:)
          return true if threshold.nil?

          retry_count < threshold
        end

        def extract_retry_count(headers)
          return 0 if headers.nil?

          count = headers[RETRY_COUNT_HEADER] || headers[RETRY_COUNT_HEADER.to_sym] || 0
          count.to_i
        end

        def retry_threshold
          threshold = nil
          if defined?(Legion::Settings)
            threshold = Legion::Settings.dig(:fleet, :poison_message_threshold)
            threshold ||= Legion::Settings.dig(:transport, :retry_threshold)
          end
          threshold || DEFAULT_THRESHOLD
        rescue StandardError
          DEFAULT_THRESHOLD
        end
      end
    end
  end
end
