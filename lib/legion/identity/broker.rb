# frozen_string_literal: true

require 'concurrent'

module Legion
  module Identity
    module Broker
      GROUPS_CACHE_TTL = 60

      class << self
        def token_for(provider_name)
          renewer = renewers[provider_name.to_sym]
          return nil unless renewer

          lease = renewer.current_lease
          lease&.valid? ? lease.token : nil
        end

        def credentials_for(provider_name, service: nil)
          renewer = renewers[provider_name.to_sym]
          return nil unless renewer

          lease = renewer.current_lease
          return nil unless lease&.valid?

          { token: lease.token, provider: provider_name, service: service, lease: lease }
        end

        def register_provider(provider_name, provider:, lease:)
          name = provider_name.to_sym
          renewers[name]&.stop!
          renewers[name] = LeaseRenewer.new(
            provider_name: name,
            provider:      provider,
            lease:         lease
          )
        end

        def authenticated?
          Identity::Process.resolved?
        end

        def groups
          cached = @groups_cache&.get
          return cached[:groups] if cached && (Time.now - cached[:fetched_at]) < GROUPS_CACHE_TTL

          return cached[:groups] if cached && !@groups_fetch_in_progress.make_true

          begin
            fetched = fetch_groups
            @groups_cache.set({ groups: fetched, fetched_at: Time.now })
            fetched
          ensure
            @groups_fetch_in_progress.make_false
          end
        end

        def invalidate_groups_cache!
          @groups_cache.set(nil)
        end

        def emails
          process_state = Identity::Process.identity_hash
          metadata = process_state[:metadata] || {}
          Array(metadata[:emails])
        end

        def providers
          renewers.keys
        end

        def leases
          renewers.transform_values { |r| r.current_lease&.to_h }
        end

        def shutdown
          renewers.each_value do |r|
            r.stop!
          rescue Exception # rubocop:disable Lint/RescueException
            nil
          end
          renewers.clear
        end

        def reset!
          shutdown
          @groups_cache = Concurrent::AtomicReference.new(nil)
          @groups_fetch_in_progress = Concurrent::AtomicBoolean.new(false)
        end

        private

        def renewers
          @renewers ||= Concurrent::Hash.new
        end

        def fetch_groups
          process_groups = Identity::Process.identity_hash[:groups]
          return process_groups if process_groups && !process_groups.empty?

          return db_groups if db_available?

          []
        end

        def db_groups
          return [] unless defined?(Legion::Data) && Legion::Data.respond_to?(:connected?) && Legion::Data.connected?

          model = begin
            Legion::Data::Model::IdentityGroupMembership
          rescue StandardError
            nil
          end
          return [] unless model

          principal_id = Identity::Process.id
          memberships = model.where(principal_id: principal_id, status: 'active').all
          memberships.filter_map do |m|
            m.group.name
          rescue StandardError
            nil
          end
        rescue StandardError => e
          log_warn("Broker.db_groups failed: #{e.message}")
          []
        end

        def db_available?
          defined?(Legion::Data) &&
            Legion::Data.respond_to?(:connected?) &&
            Legion::Data.connected?
        end

        def log_warn(message)
          if defined?(Legion::Logging) && Legion::Logging.respond_to?(:warn)
            Legion::Logging.warn("[Identity::Broker] #{message}")
          else
            $stderr.puts "[Identity::Broker] #{message}" # rubocop:disable Style/StderrPuts
          end
        end
      end

      # Initialize atomics at module definition time
      @groups_cache = Concurrent::AtomicReference.new(nil)
      @groups_fetch_in_progress = Concurrent::AtomicBoolean.new(false)
    end
  end
end
