# frozen_string_literal: true

require 'concurrent'

module Legion
  module Readiness
    REQUIRED_COMPONENTS = %i[settings crypt transport cache data extensions api].freeze
    OPTIONAL_COMPONENTS = %i[rbac llm apollo gaia identity].freeze
    COMPONENTS = (REQUIRED_COMPONENTS + OPTIONAL_COMPONENTS).freeze
    DRAIN_TIMEOUT = 5

    class << self
      def status
        @status ||= Concurrent::Hash.new
      end

      def mark_ready(component)
        status[component.to_sym] = true
        Legion::Logging.info "[Readiness] #{component} is ready" if defined?(Legion::Logging)
      end

      def mark_not_ready(component)
        status[component.to_sym] = false
        Legion::Logging.debug "[Readiness] #{component} is not ready" if defined?(Legion::Logging)
      end

      def mark_skipped(component)
        status[component.to_sym] = :skipped
        Legion::Logging.debug "[Readiness] #{component} skipped (optional)" if defined?(Legion::Logging)
      end

      def ready?(component = nil)
        if component
          result = [true, :skipped].include?(status[component.to_sym])
          Legion::Logging.warn "[Readiness] #{component} is not ready" if !result && defined?(Legion::Logging)
          return result
        end

        not_ready = COMPONENTS.reject { |c| [true, :skipped].include?(status[c]) }
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
        @status = nil
      end

      def to_h
        COMPONENTS.to_h do |c|
          val = status[c]
          [c, [true, :skipped].include?(val)]
        end
      end
    end
  end
end
