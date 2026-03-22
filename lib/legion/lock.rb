# frozen_string_literal: true

require 'securerandom'

module Legion
  module Lock
    class NotAcquired < StandardError; end

    RELEASE_SCRIPT = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA

    EXTEND_SCRIPT = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("pexpire", KEYS[1], ARGV[2])
      else
        return 0
      end
    LUA

    class << self
      def acquire(name, ttl: 30_000)
        token = SecureRandom.uuid
        key = lock_key(name)
        result = with_redis { |conn| conn.set(key, token, nx: true, px: ttl) }
        result ? token : nil
      rescue StandardError
        nil
      end

      def release(name, token)
        key = lock_key(name)
        result = with_redis { |conn| conn.eval(RELEASE_SCRIPT, keys: [key], argv: [token]) }
        result == 1
      rescue StandardError
        false
      end

      def with_lock(name, ttl: 30_000)
        token = acquire(name, ttl: ttl)
        raise NotAcquired, "could not acquire lock: #{name}" unless token

        yield
      ensure
        release(name, token) if token
      end

      def extend_lock(name, token, ttl: 30_000)
        key = lock_key(name)
        result = with_redis { |conn| conn.eval(EXTEND_SCRIPT, keys: [key], argv: [token, ttl.to_s]) }
        result == 1
      rescue StandardError
        false
      end

      def locked?(name)
        with_redis { |conn| conn.exists?(lock_key(name)) }
      rescue StandardError
        false
      end

      private

      def lock_key(name)
        "legion:lock:#{name}"
      end

      def with_redis(&)
        Legion::Cache.client.with(&)
      end
    end
  end
end
