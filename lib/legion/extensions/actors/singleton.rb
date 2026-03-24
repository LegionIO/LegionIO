# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Singleton
        def self.included(base)
          base.prepend(ExecutionGuard)
        end

        def singleton_role
          self.class.name&.gsub('::', '_')&.downcase || 'unknown'
        end

        def singleton_ttl
          [time * 3, 30].max
        end

        module ExecutionGuard
          def initialize(**opts)
            @leader_token = nil
            super
          end

          private

          def singleton_enabled?
            return false unless defined?(Legion::Settings)

            cluster = Legion::Settings[:cluster]
            cluster.is_a?(Hash) && cluster[:singleton_enabled] == true
          rescue StandardError
            false
          end

          def skip_or_run(&)
            return super unless singleton_enabled?
            return super unless defined?(Legion::Lock) || defined?(Legion::Cluster::Lock)

            role = singleton_role
            ttl_secs = singleton_ttl

            if @leader_token.nil?
              @leader_token = acquire_singleton_lock(role, ttl_secs)
              return unless @leader_token
            else
              extended = extend_singleton_lock(role, @leader_token, ttl_secs)
              unless extended
                @leader_token = acquire_singleton_lock(role, ttl_secs)
                return unless @leader_token
              end
            end

            super
          end

          def acquire_singleton_lock(role, ttl_secs)
            if defined?(Legion::Cluster::Lock)
              Legion::Cluster::Lock.acquire(name: "leader:#{role}", ttl: ttl_secs)
            else
              Legion::Lock.acquire("leader:#{role}", ttl: ttl_secs * 1000)
            end
          end

          def extend_singleton_lock(role, token, ttl_secs)
            if defined?(Legion::Cluster::Lock)
              Legion::Cluster::Lock.extend_lock(name: "leader:#{role}", token: token, ttl: ttl_secs)
            else
              Legion::Lock.extend_lock("leader:#{role}", token, ttl: ttl_secs * 1000)
            end
          end
        end
      end
    end
  end
end
