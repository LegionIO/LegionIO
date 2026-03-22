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

          def skip_or_run(&)
            return super unless defined?(Legion::Lock)

            role = singleton_role
            ttl_ms = singleton_ttl * 1000

            unless @leader_token
              @leader_token = Legion::Lock.acquire("leader:#{role}", ttl: ttl_ms)
              return unless @leader_token
            end

            extended = Legion::Lock.extend_lock("leader:#{role}", @leader_token, ttl: ttl_ms)
            unless extended
              @leader_token = Legion::Lock.acquire("leader:#{role}", ttl: ttl_ms)
              return unless @leader_token
            end

            super
          end
        end
      end
    end
  end
end
