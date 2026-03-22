# frozen_string_literal: true

require 'sinatra/base'
require 'concurrent-ruby'

module Legion
  class API < Sinatra::Base
    module Middleware
      class RateLimit
        SKIP_PATHS = %w[/api/health /api/ready /api/metrics /api/openapi.json].freeze
        WINDOW_SIZE = 60

        class MemoryStore
          def initialize
            @counters = Concurrent::Hash.new
          end

          def increment(key, window)
            composite = "#{key}:#{window}"
            @counters[composite] = (@counters[composite] || 0) + 1
          end

          def count(key, window)
            @counters["#{key}:#{window}"] || 0
          end

          def reap!
            cutoff = (Time.now.to_i / WINDOW_SIZE * WINDOW_SIZE) - (WINDOW_SIZE * 2)
            @counters.each_key do |k|
              window = k.split(':').last.to_i
              @counters.delete(k) if window < cutoff
            end
          end
        end

        class CacheStore
          def increment(key, window)
            cache_key = "legion:ratelimit:#{key}:#{window}"
            current = Legion::Cache.get(cache_key).to_i
            Legion::Cache.set(cache_key, current + 1, ttl: 120)
            current + 1
          end

          def count(key, window)
            Legion::Cache.get("legion:ratelimit:#{key}:#{window}").to_i
          end

          def reap!; end
        end

        def initialize(app, **opts)
          @app = app
          @enabled = opts.fetch(:enabled, true)
          @limits = {
            per_ip:     opts.fetch(:per_ip, 60),
            per_agent:  opts.fetch(:per_agent, 300),
            per_tenant: opts.fetch(:per_tenant, 3000)
          }
          @store = select_store
          @reap_counter = 0
        end

        def call(env)
          return @app.call(env) unless @enabled
          return @app.call(env) if skip_path?(env['PATH_INFO'])

          result = check_limits(env)
          if result[:limited]
            rate_limit_response(result)
          else
            status, headers, body = @app.call(env)
            [status, headers.merge(rate_limit_headers(result)), body]
          end
        rescue StandardError
          @app.call(env)
        end

        private

        def select_store
          if defined?(Legion::Cache) && Legion::Cache.respond_to?(:connected?) && Legion::Cache.connected?
            CacheStore.new
          else
            MemoryStore.new
          end
        end

        def skip_path?(path)
          SKIP_PATHS.any? { |p| path.start_with?(p) }
        end

        def current_window
          Time.now.to_i / WINDOW_SIZE * WINDOW_SIZE
        end

        def check_limits(env)
          window = current_window
          reset_at = window + WINDOW_SIZE
          most_restrictive = { limited: false, limit: 0, remaining: 0, reset: reset_at }

          ip = env['REMOTE_ADDR'] || 'unknown'
          ip_count = @store.increment("ip:#{ip}", window)
          update_most_restrictive(most_restrictive, ip_count, @limits[:per_ip], reset_at)

          worker_id = env['legion.worker_id']
          if worker_id
            agent_count = @store.increment("agent:#{worker_id}", window)
            update_most_restrictive(most_restrictive, agent_count, @limits[:per_agent], reset_at)
          end

          owner_msid = env['legion.owner_msid']
          if owner_msid
            tenant_count = @store.increment("tenant:#{owner_msid}", window)
            update_most_restrictive(most_restrictive, tenant_count, @limits[:per_tenant], reset_at)
          end

          lazy_reap!
          most_restrictive
        end

        def update_most_restrictive(result, count, limit, reset_at)
          remaining = [limit - count, 0].max
          if count > limit
            result[:limited] = true
            result[:limit] = limit
            result[:remaining] = 0
            result[:reset] = reset_at
          elsif result[:limit].zero? || remaining < result[:remaining]
            result[:limit] = limit
            result[:remaining] = remaining
            result[:reset] = reset_at
          end
        end

        def lazy_reap!
          @reap_counter += 1
          return unless @reap_counter >= 100

          @reap_counter = 0
          @store.reap!
        end

        def rate_limit_headers(result)
          {
            'X-RateLimit-Limit'     => result[:limit].to_s,
            'X-RateLimit-Remaining' => result[:remaining].to_s,
            'X-RateLimit-Reset'     => result[:reset].to_s
          }
        end

        def rate_limit_response(result)
          retry_after = [result[:reset] - Time.now.to_i, 1].max
          Legion::Logging.warn "API rate limit exceeded: limit=#{result[:limit]} retry_after=#{retry_after}s" if defined?(Legion::Logging)
          body = Legion::JSON.dump({
                                     error: { code:    'rate_limit_exceeded',
                                              message: "Rate limit exceeded. Try again after #{retry_after} seconds." },
                                     meta:  { timestamp: Time.now.utc.iso8601 }
                                   })
          headers = rate_limit_headers(result).merge(
            'content-type' => 'application/json',
            'Retry-After'  => retry_after.to_s
          )
          [429, headers, [body]]
        end
      end
    end
  end
end
