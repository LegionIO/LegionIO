# frozen_string_literal: true

module Legion
  module Events
    class << self
      def listeners
        @listeners ||= Hash.new { |h, k| h[k] = [] }
      end

      def on(event_name, &block)
        listeners[event_name.to_s] << block
        block
      end

      def off(event_name, block = nil)
        if block
          listeners[event_name.to_s].delete(block)
        else
          listeners.delete(event_name.to_s)
        end
      end

      def emit(event_name, **payload)
        event = {
          event:     event_name.to_s,
          timestamp: Time.now,
          **payload
        }

        listeners[event_name.to_s].each do |listener|
          listener.call(event)
        rescue StandardError => e
          Legion::Logging.error "Event listener error on #{event_name}: #{e.message}"
          Legion::Logging.error e.backtrace&.first(5)
        end

        # Also fire wildcard listeners
        listeners['*'].each do |listener|
          listener.call(event)
        rescue StandardError => e
          Legion::Logging.error "Wildcard event listener error: #{e.message}"
        end

        event
      end

      def once(event_name, &block)
        wrapper = proc do |event|
          block.call(event)
          off(event_name, wrapper)
        end
        on(event_name, &wrapper)
      end

      def clear
        @listeners = nil
      end

      def listener_count(event_name = nil)
        if event_name
          listeners[event_name.to_s].size
        else
          listeners.values.sum(&:size)
        end
      end
    end
  end
end
