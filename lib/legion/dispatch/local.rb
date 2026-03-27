# frozen_string_literal: true

require 'concurrent-ruby'

module Legion
  module Dispatch
    class Local
      def initialize(pool_size: nil)
        max = pool_size || Legion::Settings.dig(:dispatch, :local_pool_size) || 8
        @pool = Concurrent::FixedThreadPool.new(max)
      end

      def start; end

      def submit(&block)
        @pool.post do
          block.call
        rescue StandardError => e
          Legion::Logging.error "[Dispatch::Local] #{e.message}" if defined?(Legion::Logging)
          Legion::Logging.debug e.backtrace&.first(5) if defined?(Legion::Logging)
        end
      end

      def stop
        return unless @pool.running?

        @pool.shutdown
        @pool.wait_for_termination(15)
      end

      def capacity
        {
          pool_size:    @pool.max_length,
          queue_length: @pool.queue_length,
          running:      @pool.running?
        }
      end
    end
  end
end
