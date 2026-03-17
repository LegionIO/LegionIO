# frozen_string_literal: true

module Legion
  module Chat
    class NotificationQueue
      PRIORITIES = { critical: 0, info: 1, debug: 2 }.freeze

      def initialize(max_size: 50)
        @queue = []
        @mutex = Mutex.new
        @max_size = max_size
      end

      def push(message:, priority: :info, source: nil)
        @mutex.synchronize do
          @queue << { message: message, priority: priority, source: source, at: Time.now }
          @queue.shift if @queue.size > @max_size
        end
      end

      def pop_all(max_priority: :info)
        @mutex.synchronize do
          threshold = PRIORITIES[max_priority] || 1
          pending = @queue.select { |n| PRIORITIES[n[:priority]] <= threshold }
          @queue -= pending
          pending.sort_by { |n| PRIORITIES[n[:priority]] }
        end
      end

      def has_critical? # rubocop:disable Naming/PredicatePrefix
        @mutex.synchronize { @queue.any? { |n| n[:priority] == :critical } }
      end

      def size
        @mutex.synchronize { @queue.size }
      end

      def clear
        @mutex.synchronize { @queue.clear }
      end
    end
  end
end
