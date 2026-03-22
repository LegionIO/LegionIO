# frozen_string_literal: true

require 'concurrent'
require_relative 'lock'

module Legion
  module Leader
    class << self
      def elect(role, ttl: 30)
        ttl_ms = ttl * 1000
        token = Legion::Lock.acquire("leader:#{role}", ttl: ttl_ms)
        return nil unless token

        @leaders ||= {}
        @leaders[role.to_sym] = { token: token, ttl_ms: ttl_ms }
        token
      end

      def leader?(role)
        return false unless @leaders&.dig(role.to_sym, :token)

        Legion::Lock.locked?("leader:#{role}")
      end

      def resign(role)
        return false unless @leaders&.dig(role.to_sym)

        entry = @leaders.delete(role.to_sym)
        stop_renewal(role)
        Legion::Lock.release("leader:#{role}", entry[:token])
      end

      def with_leadership(role, ttl: 30)
        token = elect(role, ttl: ttl)
        raise Legion::Lock::NotAcquired, "could not elect leader for: #{role}" unless token

        start_renewal(role, ttl)
        yield
      ensure
        resign(role)
      end

      def reset!
        @leaders&.each_key { |role| resign(role) }
        @leaders = {}
        @renewals&.each_value(&:shutdown)
        @renewals = {}
      end

      private

      def start_renewal(role, ttl)
        @renewals ||= {}
        interval = [ttl / 3, 1].max
        entry = @leaders[role.to_sym]
        return unless entry

        @renewals[role.to_sym] = Concurrent::TimerTask.new(execution_interval: interval) do
          success = Legion::Lock.extend_lock("leader:#{role}", entry[:token], ttl: entry[:ttl_ms])
          unless success
            log_warn("Lost leadership for #{role}")
            @renewals[role.to_sym]&.shutdown
          end
        end
        @renewals[role.to_sym].execute
      end

      def stop_renewal(role)
        @renewals ||= {}
        @renewals.delete(role.to_sym)&.shutdown
      end

      def log_warn(msg)
        Legion::Logging.warn(msg) if defined?(Legion::Logging)
      end
    end
  end
end
