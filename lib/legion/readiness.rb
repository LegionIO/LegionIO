# frozen_string_literal: true

module Legion
  module Readiness
    COMPONENTS = %i[settings crypt transport cache data rbac llm gaia extensions api].freeze
    DRAIN_TIMEOUT = 5

    class << self
      def status
        @status ||= {}
      end

      def mark_ready(component)
        status[component.to_sym] = true
        Legion::Logging.info "[Readiness] #{component} is ready" if defined?(Legion::Logging)
      end

      def mark_not_ready(component)
        status[component.to_sym] = false
        Legion::Logging.debug "[Readiness] #{component} is not ready" if defined?(Legion::Logging)
      end

      def ready?(component = nil)
        if component
          result = status[component.to_sym] == true
          Legion::Logging.warn "[Readiness] #{component} is not ready" if !result && defined?(Legion::Logging)
          return result
        end

        not_ready = COMPONENTS.reject { |c| status[c] == true }
        not_ready.each { |c| Legion::Logging.warn "[Readiness] #{c} is not ready" } if !not_ready.empty? && defined?(Legion::Logging)
        not_ready.empty?
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
        COMPONENTS.to_h do |c|
          [c, status[c] == true]
        end
      end
    end
  end
end
