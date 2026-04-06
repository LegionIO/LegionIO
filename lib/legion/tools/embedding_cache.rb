# frozen_string_literal: true

require 'digest'

module Legion
  module Tools
    module EmbeddingCache
      MIGRATION_PATH = File.expand_path('embedding_cache/migrations', __dir__)
      L0_MAX_ENTRIES = 1000
      CACHE_TTL = 86_400 # 24 hours

      # L0: in-memory - always available
      @memory_cache = {}
      @memory_mutex = Mutex.new

      class << self
        def log
          Legion::Logging.respond_to?(:logger) ? Legion::Logging.logger : nil
        end

        def handle_exception(e, **opts)
          log&.warn("[Tools::EmbeddingCache] #{opts[:operation]}: #{e.message}")
        end

        def setup
          Legion::Data::Local.register_migrations(name: 'embedding_cache', path: MIGRATION_PATH)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_setup)
        end

        def available?
          true # L0 is always available
        end

        def content_hash(text)
          Digest::MD5.hexdigest(text.to_s)
        end

        # --- 5-tier read cascade ---

        def lookup(content_hash:, model:)
          key = "embed:#{content_hash}:#{model}"

          # L0
          vec = memory_get(key)
          return vec if vec

          # Tier 1
          vec = cache_local_get(key)
          if vec
            memory_set(key, vec)
            return vec
          end

          # Tier 2
          vec = cache_global_get(key)
          if vec
            memory_set(key, vec)
            cache_local_set(key, vec)
            return vec
          end

          # Tier 3
          row = data_local_get(content_hash, model)
          if row
            vec = parse_vector(row[:vector])
            if vec
              memory_set(key, vec)
              cache_local_set(key, vec)
              cache_global_set(key, vec)
              return vec
            end
          end

          # Tier 4
          row = data_global_get(content_hash, model)
          if row
            vec = parse_vector(row[:vector])
            if vec
              memory_set(key, vec)
              cache_local_set(key, vec)
              cache_global_set(key, vec)
              data_local_store(content_hash: content_hash, model: model,
                               tool_name: row[:tool_name], vector: vec)
              return vec
            end
          end

          nil
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_lookup)
          nil
        end

        def bulk_lookup(content_hashes:, model:)
          return {} if content_hashes.empty?

          result = {}
          remaining = content_hashes.dup

          # L0
          remaining.dup.each do |h|
            vec = memory_get("embed:#{h}:#{model}")
            next unless vec

            result[h] = vec
            remaining.delete(h)
          end

          # Tier 1
          remaining.dup.each do |h|
            vec = cache_local_get("embed:#{h}:#{model}")
            next unless vec

            result[h] = vec
            memory_set("embed:#{h}:#{model}", vec)
            remaining.delete(h)
          end

          # Tier 2
          remaining.dup.each do |h|
            vec = cache_global_get("embed:#{h}:#{model}")
            next unless vec

            result[h] = vec
            memory_set("embed:#{h}:#{model}", vec)
            cache_local_set("embed:#{h}:#{model}", vec)
            remaining.delete(h)
          end

          # Tier 3
          bulk_data_lookup(remaining, model, result, :local) if remaining.any?

          # Tier 4
          bulk_data_lookup(remaining, model, result, :global) if remaining.any?

          result
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_bulk_lookup)
          result || {}
        end

        # Write to all 5 tiers
        def store(content_hash:, model:, tool_name:, vector:)
          key = "embed:#{content_hash}:#{model}"
          memory_set(key, vector)
          cache_local_set(key, vector)
          cache_global_set(key, vector)
          data_local_store(content_hash: content_hash, model: model,
                           tool_name: tool_name, vector: vector)
          data_global_store(content_hash: content_hash, model: model,
                            tool_name: tool_name, vector: vector)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_store)
        end

        def bulk_store(entries)
          return if entries.nil? || entries.empty?

          cache_hash = {}
          entries.each do |entry|
            key = "embed:#{entry[:content_hash]}:#{entry[:model]}"
            memory_set(key, entry[:vector])
            cache_hash[key] = entry[:vector]
          end

          bulk_cache_store(cache_hash)
          bulk_data_local_store(entries) if data_local_available?
          bulk_data_global_store(entries) if data_global_available?
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_bulk_store)
        end

        def clear
          @memory_mutex.synchronize { @memory_cache.clear }
          data_local_connection[:tool_embedding_cache].delete if data_local_available?
          data_global_connection[:tool_embedding_cache].delete if data_global_available?
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_clear)
        end

        def stats
          {
            memory:       @memory_mutex.synchronize { @memory_cache.size },
            cache_local:  cache_local_available?,
            cache_global: cache_global_available?,
            data_local:   data_local_available? ? data_local_connection[:tool_embedding_cache].count : 0,
            data_global:  data_global_available? ? data_global_connection[:tool_embedding_cache].count : 0
          }
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :embedding_cache_stats)
          {}
        end

        private

        # --- L0 ---
        def memory_get(key)
          @memory_mutex.synchronize { @memory_cache[key]&.dup }
        end

        def memory_set(key, vector)
          @memory_mutex.synchronize do
            if @memory_cache.size >= L0_MAX_ENTRIES && !@memory_cache.key?(key)
              @memory_cache.delete(@memory_cache.keys.first)
            end
            @memory_cache[key] = vector.dup.freeze
          end
        end

        # --- Tier availability ---
        def cache_local_available?
          defined?(Legion::Cache) && Legion::Cache.local.enabled? && Legion::Cache.local.connected?
        rescue StandardError
          false
        end

        def cache_global_available?
          defined?(Legion::Cache) && Legion::Cache.enabled? && Legion::Cache.connected?
        rescue StandardError
          false
        end

        def data_local_available?
          defined?(Legion::Data::Local) && Legion::Data::Local.connected? &&
            Legion::Data::Local.connection.table_exists?(:tool_embedding_cache)
        rescue StandardError
          false
        end

        def data_global_available?
          defined?(Legion::Data) && Legion::Data.connected? &&
            Legion::Data.connection.table_exists?(:tool_embedding_cache)
        rescue StandardError
          false
        end

        # --- Cache tier helpers ---
        def cache_local_get(key)
          return nil unless cache_local_available?

          result = Legion::Cache.local.get(key)
          result.is_a?(Array) ? result : nil
        rescue StandardError
          nil
        end

        def cache_local_set(key, vector)
          return unless cache_local_available?

          Legion::Cache.local.set(key, vector, ttl: CACHE_TTL, async: false)
        rescue StandardError
          nil
        end

        def cache_global_get(key)
          return nil unless cache_global_available?

          result = Legion::Cache.get(key)
          result.is_a?(Array) ? result : nil
        rescue StandardError
          nil
        end

        def cache_global_set(key, vector)
          return unless cache_global_available?

          Legion::Cache.set(key, vector, ttl: CACHE_TTL, async: false)
        rescue StandardError
          nil
        end

        # --- Data tier helpers ---
        def data_local_connection
          Legion::Data::Local.connection
        end

        def data_global_connection
          Legion::Data.connection
        end

        def data_local_get(content_hash, model)
          return nil unless data_local_available?

          data_local_connection[:tool_embedding_cache]
            .where(content_hash: content_hash, model: model).first
        rescue StandardError
          nil
        end

        def data_global_get(content_hash, model)
          return nil unless data_global_available?

          data_global_connection[:tool_embedding_cache]
            .where(content_hash: content_hash, model: model).first
        rescue StandardError
          nil
        end

        def data_local_store(content_hash:, model:, tool_name:, vector:)
          return unless data_local_available?

          vec_json = vector.is_a?(String) ? vector : Legion::JSON.dump(vector)
          Legion::Data::Local.upsert(
            :tool_embedding_cache,
            { content_hash: content_hash, model: model, tool_name: tool_name,
              vector: vec_json, embedded_at: Time.now.utc.iso8601 },
            conflict_keys: %i[content_hash model]
          )
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :data_local_store)
        end

        def data_global_store(content_hash:, model:, tool_name:, vector:)
          return unless data_global_available?

          vec_json = vector.is_a?(String) ? vector : Legion::JSON.dump(vector)
          data_global_connection[:tool_embedding_cache]
            .insert_conflict(target: %i[content_hash model], update: {
                               vector: vec_json, tool_name: tool_name, embedded_at: Time.now.utc.iso8601
                             })
            .insert(content_hash: content_hash, model: model, tool_name: tool_name,
                    vector: vec_json, embedded_at: Time.now.utc.iso8601)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :data_global_store)
        end

        # --- Bulk helpers ---
        def bulk_cache_store(cache_hash)
          return if cache_hash.empty?

          if cache_local_available?
            begin
              Legion::Cache.local.mset(cache_hash, ttl: CACHE_TTL, async: false)
            rescue StandardError => e
              handle_exception(e, level: :debug, handled: true, operation: :bulk_cache_local_mset)
            end
          end

          return unless cache_global_available?

          Legion::Cache.mset(cache_hash, ttl: CACHE_TTL, async: false)
        rescue StandardError => e
          handle_exception(e, level: :debug, handled: true, operation: :bulk_cache_global_mset)
        end

        def bulk_data_lookup(remaining, model, result, tier)
          available = tier == :local ? data_local_available? : data_global_available?
          return unless available

          conn = tier == :local ? data_local_connection : data_global_connection
          conn[:tool_embedding_cache].where(content_hash: remaining, model: model).all.each do |row|
            vec = parse_vector(row[:vector])
            next unless vec

            h = row[:content_hash]
            result[h] = vec
            memory_set("embed:#{h}:#{model}", vec)
            cache_local_set("embed:#{h}:#{model}", vec)
            cache_global_set("embed:#{h}:#{model}", vec)
            remaining.delete(h)
          end
        end

        def bulk_data_local_store(entries)
          now = Time.now.utc.iso8601
          ds = data_local_connection[:tool_embedding_cache]
          data_local_connection.transaction do
            entries.each do |entry|
              vec_json = entry[:vector].is_a?(String) ? entry[:vector] : Legion::JSON.dump(entry[:vector])
              ds.insert_conflict(target: %i[content_hash model], update: {
                                   vector: vec_json, tool_name: entry[:tool_name], embedded_at: now
                                 }).insert(content_hash: entry[:content_hash], model: entry[:model],
                                           tool_name: entry[:tool_name], vector: vec_json, embedded_at: now)
            end
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :bulk_data_local_store)
        end

        def bulk_data_global_store(entries)
          now = Time.now.utc.iso8601
          ds = data_global_connection[:tool_embedding_cache]
          data_global_connection.transaction do
            entries.each do |entry|
              vec_json = entry[:vector].is_a?(String) ? entry[:vector] : Legion::JSON.dump(entry[:vector])
              ds.insert_conflict(target: %i[content_hash model], update: {
                                   vector: vec_json, tool_name: entry[:tool_name], embedded_at: now
                                 }).insert(content_hash: entry[:content_hash], model: entry[:model],
                                           tool_name: entry[:tool_name], vector: vec_json, embedded_at: now)
            end
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :bulk_data_global_store)
        end

        def parse_vector(json_str)
          return nil unless json_str

          vec = json_str.is_a?(Array) ? json_str : Legion::JSON.load(json_str)
          vec.is_a?(Array) ? vec : nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
