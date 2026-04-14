# frozen_string_literal: true

# In-memory cache that mimics Legion::Cache interface for integration testing.
# Supports get, set, set_nx, delete, and TTL tracking.
module Fleet
  module Test
    class MockCache
      attr_reader :store, :ttls

      def initialize
        @store = {}
        @ttls = {}
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          return nil if expired?(key)

          @store[key]
        end
      end

      def set(key, value, ttl: nil)
        @mutex.synchronize do
          @store[key] = value
          @ttls[key] = Time.now + ttl if ttl
          value
        end
      end

      # Atomic set-if-not-exists (mimics Redis SET NX EX)
      def set_nx(key, value, ttl: nil)
        @mutex.synchronize do
          return false if @store.key?(key) && !expired?(key)

          @store[key] = value
          @ttls[key] = Time.now + ttl if ttl
          true
        end
      end

      def delete(key)
        @mutex.synchronize do
          @store.delete(key)
          @ttls.delete(key)
        end
      end

      def exists?(key)
        @mutex.synchronize { @store.key?(key) && !expired?(key) }
      end

      def clear
        @mutex.synchronize do
          @store.clear
          @ttls.clear
        end
      end

      def keys(pattern = '*')
        @mutex.synchronize do
          regex = Regexp.new("\\A#{Regexp.escape(pattern).gsub('\\*', '.*')}\\z")
          @store.keys.grep(regex)
        end
      end

      private

      def expired?(key)
        return false unless @ttls.key?(key)

        Time.now > @ttls[key]
      end
    end
  end
end
