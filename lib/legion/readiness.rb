# frozen_string_literal: true

module Legion
  module Readiness
    COMPONENTS = %i[settings crypt transport cache data extensions api].freeze
    DRAIN_TIMEOUT = 5

    class << self
      def status
        @status ||= {}
      end

      def mark_ready(component)
        status[component.to_sym] = true
        Legion::Logging.debug("#{component} is ready")
      end

      def mark_not_ready(component)
        status[component.to_sym] = false
        Legion::Logging.debug("#{component} is not ready")
      end

      def ready?(component = nil)
        return status[component.to_sym] == true if component

        COMPONENTS.all? { |c| status[c] == true }
      end

      def wait_until_not_ready(*components, timeout: DRAIN_TIMEOUT)
        deadline = Time.now + timeout
        loop do
          break if components.all? { |c| status[c] != true }
          break if Time.now > deadline

          sleep(0.1)
        end
      end

      def reset
        @status = {}
      end

      def to_h
        COMPONENTS.each_with_object({}) do |c, h|
          h[c] = status[c] == true
        end
      end
    end
  end
end
