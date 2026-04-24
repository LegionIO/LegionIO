# frozen_string_literal: true

require 'concurrent'

module Legion
  module Identity
    module Broker
      GROUPS_CACHE_TTL = 60
      AUDIT_QUEUE_MAX = 1000
      AUDIT_DROP_LOG_INTERVAL = 100

      class << self
        def token_for(provider_name, qualifier: nil, for_context: nil, purpose: nil, context: nil)
          name = provider_name.to_sym
          resolved = resolve_qualifier(name, qualifier: qualifier, for_context: for_context)
          lease = lease_for(name, qualifier: resolved)
          token = lease&.valid? ? lease.token : nil
          emit_audit(provider: name, qualifier: resolved, purpose: purpose, context: context, granted: !token.nil?)
          token
        end

        def lease_for(provider_name, qualifier: nil)
          name = provider_name.to_sym
          resolved = qualifier || default_qualifier_for(name)
          key = [name, resolved].freeze

          renewer = renewers[key]
          return renewer.current_lease if renewer

          static_ref = static_leases[key]
          static_ref&.get
        end

        def renewer_for(provider_name, qualifier: nil)
          name = provider_name.to_sym
          resolved = qualifier || default_qualifier_for(name)
          renewers[[name, resolved].freeze]
        end

        def credentials_for(provider_name, qualifier: nil, service: nil)
          name = provider_name.to_sym
          resolved = qualifier || default_qualifier_for(name)
          lease = lease_for(name, qualifier: resolved)
          return nil unless lease&.valid?

          { token: lease.token, provider: name, service: service, lease: lease }
        end

        def register_provider(provider_name, provider:, lease:, qualifier: :default, default: false)
          name = provider_name.to_sym
          qual = qualifier
          key = [name, qual].freeze

          # Set default qualifier: first registration or explicit default: true
          default_qualifiers[name] = qual if default || !default_qualifiers.key?(name)

          # Store provider instance (first-write-wins per provider name)
          provider_instances[name] ||= provider

          # Stop existing renewer for this specific tuple key
          renewers[key]&.stop!

          if lease&.expires_at.nil? && !lease&.renewable
            # Static credential — store without a background renewal thread
            renewers.delete(key)
            static_leases[key] = Concurrent::AtomicReference.new(lease)
          else
            # Dynamic credential — create LeaseRenewer
            static_leases.delete(key)
            renewers[key] = LeaseRenewer.new(
              provider_name: name,
              provider:      provider,
              lease:         lease
            )
          end
        end

        def refresh_credential(provider_name, qualifier: nil)
          name = provider_name.to_sym
          resolved = qualifier || default_qualifier_for(name)
          key = [name, resolved].freeze

          ref = static_leases[key]
          return false unless ref

          provider = provider_instances[name]
          return false unless provider.respond_to?(:provide_token)

          new_lease = provider.provide_token
          return false unless new_lease&.valid?

          ref.set(new_lease)
          true
        end

        def authenticated?
          Identity::Process.resolved?
        end

        def groups
          cached = @groups_cache&.get
          return cached[:groups] if cached && (Time.now - cached[:fetched_at]) < GROUPS_CACHE_TTL

          if @groups_fetch_in_progress.make_true
            begin
              fetched = fetch_groups
              @groups_cache.set({ groups: fetched, fetched_at: Time.now })
              fetched
            ensure
              @groups_fetch_in_progress.make_false
            end
          else
            loop do
              current = @groups_cache&.get
              return current[:groups] if current

              break unless @groups_fetch_in_progress.true?

              sleep(0.01)
            end

            cached ? cached[:groups] : []
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
          all_keys = (renewers.keys + static_leases.keys)
          all_keys.map(&:first).uniq
        end

        def credentials_available(provider_name)
          name = provider_name.to_sym
          all_keys = (renewers.keys + static_leases.keys)
          all_keys.select { |k| k.first == name }.map(&:last).uniq
        end

        def leases
          result = {}
          renewers.each do |key, renewer|
            provider_name = key.first
            result[provider_name] = renewer.current_lease&.to_h
          end
          static_leases.each do |key, ref|
            provider_name = key.first
            result[provider_name] = ref.get&.to_h unless result.key?(provider_name)
          end
          result
        end

        def shutdown
          renewers.each_value do |r|
            r.stop!
          rescue Exception # rubocop:disable Lint/RescueException
            nil
          end
          renewers.clear
          static_leases.clear
          provider_instances.clear
          default_qualifiers.clear
          stop_audit_drainer
        end

        def reset!
          shutdown
          @groups_cache = Concurrent::AtomicReference.new(nil)
          @groups_fetch_in_progress = Concurrent::AtomicBoolean.new(false)
          @audit_queue = Concurrent::Array.new
          @audit_drops = Concurrent::AtomicFixnum.new(0)
          @audit_drainer = nil
          @audit_drainer_started = Concurrent::AtomicBoolean.new(false)
        end

        private

        def resolve_qualifier(provider_name, qualifier: nil, for_context: nil)
          return qualifier if qualifier

          if for_context
            provider = provider_instances[provider_name]
            if provider.respond_to?(:resolve_qualifier)
              resolved = provider.resolve_qualifier(for_context)
              return resolved if resolved
            end
          end

          default_qualifier_for(provider_name)
        end

        def default_qualifier_for(provider_name)
          default_qualifiers[provider_name] || :default
        end

        def renewers
          @renewers ||= Concurrent::Hash.new
        end

        def static_leases
          @static_leases ||= Concurrent::Hash.new
        end

        def provider_instances
          @provider_instances ||= Concurrent::Hash.new
        end

        def default_qualifiers
          @default_qualifiers ||= Concurrent::Hash.new
        end

        def audit_queue
          @audit_queue ||= Concurrent::Array.new
        end

        def emit_audit(provider:, qualifier:, purpose:, context:, granted:)
          ensure_audit_drainer_started
          event = {
            provider:  provider,
            qualifier: qualifier,
            purpose:   purpose,
            context:   context,
            granted:   granted,
            timestamp: Time.now
          }

          if audit_queue.size >= AUDIT_QUEUE_MAX
            drops = (@audit_drops ||= Concurrent::AtomicFixnum.new(0)).increment
            log_warn("Audit queue full, dropping event (total drops: #{drops})") if (drops % AUDIT_DROP_LOG_INTERVAL).zero?
          else
            audit_queue.push(event)
          end
        end

        def ensure_audit_drainer_started
          @audit_drainer_started ||= Concurrent::AtomicBoolean.new(false)
          return if @audit_drainer_started.true?
          return unless @audit_drainer_started.make_true

          @audit_drainer = Thread.new do
            loop do
              break if Thread.current[:stop]

              event = audit_queue.shift
              if event
                publish_audit_event(event)
              else
                sleep(0.1)
              end
            end
          end
          @audit_drainer.name = 'identity-broker-audit-drainer'
        end

        def stop_audit_drainer
          if @audit_drainer&.alive?
            @audit_drainer[:stop] = true
            @audit_drainer.join(2)
            @audit_drainer.kill if @audit_drainer.alive?
          end
          @audit_drainer = nil
          @audit_drainer_started = Concurrent::AtomicBoolean.new(false)
        end

        def publish_audit_event(event)
          # Future: publish to transport / log store
          # For now, this is a hook point for downstream consumers
          event
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
      @audit_queue = Concurrent::Array.new
      @audit_drops = Concurrent::AtomicFixnum.new(0)
      @audit_drainer = nil
      @audit_drainer_started = Concurrent::AtomicBoolean.new(false)
    end
  end
end
