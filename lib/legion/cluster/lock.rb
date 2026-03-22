# frozen_string_literal: true

require 'securerandom'

module Legion
  module Cluster
    module Lock
      module_function

      @tokens = if defined?(Concurrent::Map)
                  Concurrent::Map.new
                else
                  {}
                end
      @tokens_mutex = Mutex.new unless defined?(Concurrent::Map)

      def tokens
        @tokens
      end

      def backend
        if defined?(Legion::Cache) &&
           Legion::Cache.respond_to?(:const_defined?) &&
           Legion::Cache.const_defined?(:Redis, false) &&
           Legion::Cache::Redis.respond_to?(:client) &&
           !Legion::Cache::Redis.client.nil?
          :redis
        elsif defined?(Legion::Data) &&
              Legion::Data.respond_to?(:connection) &&
              !Legion::Data.connection.nil?
          :postgres
        else
          :none
        end
      end

      def acquire(name:, ttl: 30, timeout: 5) # rubocop:disable Lint/UnusedMethodArgument
        case backend
        when :redis
          acquire_redis(name: name, ttl: ttl)
        when :postgres
          acquire_postgres(name: name)
        else
          false
        end
      end

      def release(name:, token: nil)
        case backend
        when :redis
          release_redis(name: name, token: token)
        when :postgres
          release_postgres(name: name)
        else
          false
        end
      end

      def with_lock(name:, ttl: 30, timeout: 5)
        acquired = acquire(name: name, ttl: ttl, timeout: timeout)
        return unless acquired

        token = acquired == true ? nil : acquired

        begin
          yield
        ensure
          release(name: name, token: token)
        end
      end

      def lock_key(name)
        name.to_s.bytes.reduce(0) { |acc, b| ((acc * 31) + b) & 0x7FFFFFFF }
      end

      def redis_key(name)
        "legion:lock:#{name}"
      end

      def acquire_redis(name:, ttl:)
        client = Legion::Cache::Redis.client
        token = SecureRandom.hex(16)
        key = redis_key(name)
        result = client.call('SET', key, token, 'NX', 'PX', ttl * 1000)
        return nil unless result

        store_token(name, token)
        token
      rescue StandardError
        nil
      end

      def release_redis(name:, token:)
        client = Legion::Cache::Redis.client
        tok = token || fetch_token(name)
        return false unless tok

        key = redis_key(name)
        lua = <<~LUA
          if redis.call('GET', KEYS[1]) == ARGV[1] then
            redis.call('DEL', KEYS[1])
            return 1
          else
            return 0
          end
        LUA
        result = client.call('EVAL', lua, 1, key, tok)
        delete_token(name)
        result == 1
      rescue StandardError
        false
      end

      def acquire_postgres(name:)
        key = lock_key(name)
        db = Legion::Data.connection
        return false unless db

        db.fetch('SELECT pg_try_advisory_lock(?) AS acquired', key).first[:acquired]
      rescue StandardError
        false
      end

      def release_postgres(name:)
        key = lock_key(name)
        db = Legion::Data.connection
        return false unless db

        db.fetch('SELECT pg_advisory_unlock(?) AS released', key).first[:released]
      rescue StandardError
        false
      end

      def store_token(name, token)
        if defined?(Concurrent::Map)
          @tokens[name.to_s] = token
        else
          @tokens_mutex.synchronize { @tokens[name.to_s] = token }
        end
      end

      def fetch_token(name)
        if defined?(Concurrent::Map)
          @tokens[name.to_s]
        else
          @tokens_mutex.synchronize { @tokens[name.to_s] }
        end
      end

      def delete_token(name)
        if defined?(Concurrent::Map)
          @tokens.delete(name.to_s)
        else
          @tokens_mutex.synchronize { @tokens.delete(name.to_s) }
        end
      end
    end
  end
end
