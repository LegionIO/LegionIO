# frozen_string_literal: true

require 'securerandom'
require 'fileutils'
require 'concurrent/array'
require 'concurrent/atomic/atomic_reference'
require 'concurrent/atomic/atomic_boolean'
require 'concurrent/promises'

module Legion
  module Identity
    module Resolver
      TIMEOUT_SECONDS = 5

      class << self
        def register(provider)
          return if @providers.any? { |p| p.provider_name == provider.provider_name }

          @providers << provider
        end

        def resolve!(timeout: TIMEOUT_SECONDS)
          drain_pending_registrations

          auth_providers, profile_providers, fallback_providers = partition_providers

          winning_provider, winning_result, provider_results = resolve_auth(auth_providers, timeout: timeout)

          if winning_provider.nil?
            winning_provider, winning_result, fallback_results = resolve_auth(fallback_providers, timeout: timeout)
            provider_results.merge!(fallback_results) if fallback_results
          end

          unless winning_provider
            @resolved.make_false
            @composite.set(nil)
            return nil
          end

          canonical = winning_result[:canonical_name]
          trust_level = winning_provider.trust_level
          source = winning_provider.provider_name

          profile_data = resolve_profiles(profile_providers, canonical, timeout: timeout)

          composite = assemble_composite(
            provider_results, profile_data,
            winning_result: winning_result,
            trust_level:    trust_level,
            source:         source
          )

          bind_and_persist(winning_provider, composite, trust_level)
          composite
        end

        def upgrade!(provider, result)
          current = @composite.get
          return unless current

          new_trust = provider.trust_level
          new_canonical = result[:canonical_name] || current[:canonical_name]
          canonical_changed = new_canonical != current[:canonical_name]

          # Only promote the composite trust level when the new provider's trust
          # is strictly higher (lower rank index) than the current level.
          # This prevents an accidental downgrade if upgrade! is called with a
          # lower-trust provider such as one with :unverified trust.
          current_trust = current[:trust]
          effective_trust = if defined?(Legion::Identity::Trust) &&
                               Legion::Identity::Trust.respond_to?(:above?) &&
                               Legion::Identity::Trust.above?(new_trust, current_trust)
                              new_trust
                            else
                              current_trust
                            end

          new_aliases = current[:aliases].dup
          provider_identity = result[:provider_identity]
          if provider_identity
            existing = Array(new_aliases[provider.provider_name])
            new_aliases[provider.provider_name] = (existing + [provider_identity]).uniq
          end

          new_providers = current[:providers].dup
          new_providers[provider.provider_name] = {
            status:      :resolved,
            trust:       new_trust,
            resolved_at: Time.now
          }

          updated = current.merge(
            canonical_name: new_canonical,
            trust:          effective_trust,
            source:         provider.provider_name,
            aliases:        new_aliases,
            providers:      new_providers
          )

          handle_canonical_change(current[:canonical_name], new_canonical, updated) if canonical_changed

          @composite.set(updated)
          Legion::Identity::Process.bind!(provider, updated) if defined?(Legion::Identity::Process)

          if defined?(Legion::Settings) && Legion::Settings.respond_to?(:loader) && Legion::Settings.loader.respond_to?(:settings)
            Legion::Settings.loader.settings[:client] ||= {}
            Legion::Settings.loader.settings[:client][:name] = Legion::Identity::Process.queue_prefix
          end

          persist_identity_json(new_canonical, updated[:kind]) unless new_trust == :unverified

          updated
        end

        def resolved?
          @resolved.true?
        end

        def composite
          @composite.get
        end

        def providers
          @providers.dup
        end

        attr_reader :session_id

        def reset!
          @composite  = Concurrent::AtomicReference.new(nil)
          @resolved   = Concurrent::AtomicBoolean.new(false)
          @session_id = SecureRandom.uuid
        end

        def reset_all!
          reset!
          @providers = Concurrent::Array.new
        end

        private

        def drain_pending_registrations
          return unless defined?(Legion::Identity) && Legion::Identity.respond_to?(:pending_registrations)

          pending = Legion::Identity.pending_registrations
          return if pending.nil? || pending.empty?

          drained = []
          drained << pending.shift until pending.empty?
          drained.each { |p| register(p) }
        end

        def partition_providers
          auth     = []
          profile  = []
          fallback = []

          @providers.each do |p|
            case p.provider_type
            when :auth     then auth << p
            when :profile  then profile << p
            when :fallback then fallback << p
            end
          end

          auth.sort_by! { |p| [-p.priority, p.trust_weight] }
          fallback.sort_by! { |p| [-p.priority, p.trust_weight] }

          [auth, profile, fallback]
        end

        def resolve_auth(auth_providers, timeout:)
          return [nil, nil, {}] if auth_providers.empty?

          futures = auth_providers.map do |provider|
            Concurrent::Promises.future { provider.resolve }
          end

          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout
          provider_results = {}
          auth_providers.zip(futures).each do |provider, future|
            remaining = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            future.wait(remaining.positive? ? remaining : 0)
            result = future.value(0) if future.resolved?
            status = auth_future_status(future, result)

            provider_results[provider.provider_name] = {
              status:      status,
              trust:       (status == :resolved ? provider.trust_level : nil),
              resolved_at: (status == :resolved ? Time.now : nil),
              provider:    provider,
              result:      (status == :resolved ? result : nil)
            }
          end

          resolved_entries = provider_results.select { |_, v| v[:status] == :resolved }
          if resolved_entries.empty?
            [nil, nil, provider_results]
          else
            winner_name = resolved_entries.min_by do |_, v|
              p = v[:provider]
              [-p.priority, p.trust_weight]
            end&.first

            winner_info = provider_results[winner_name]
            [winner_info[:provider], winner_info[:result], provider_results]
          end
        end

        def auth_future_status(future, result)
          if future.rejected?
            :failed
          elsif !future.resolved?
            :timeout
          elsif result.is_a?(Hash) && result[:canonical_name]
            :resolved
          else
            :no_identity
          end
        end

        def resolve_profiles(profile_providers, canonical, timeout:)
          return { groups: [], profile: {}, provider_results: {} } if profile_providers.empty?

          futures = profile_providers.map do |provider|
            Concurrent::Promises.future { resolve_profile_provider(provider, canonical) }
          end

          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout
          groups = []
          profile = {}
          pr = {}

          profile_providers.zip(futures).each do |provider, future|
            remaining = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            future.wait(remaining.positive? ? remaining : 0)
            result = future.resolved? ? future.value(0) : nil

            if future.fulfilled? && result.is_a?(Hash)
              groups.concat(Array(result[:groups])) if result[:groups]
              profile.merge!(result[:profile]) if result[:profile].is_a?(Hash)
              pr[provider.provider_name] = { status: :resolved, trust: provider.trust_level, resolved_at: Time.now }
            else
              pr[provider.provider_name] = { status: (future.rejected? ? :failed : :timeout), trust: nil, resolved_at: nil }
            end
          end

          { groups: groups.uniq, profile: profile, provider_results: pr }
        end

        def resolve_profile_provider(provider, canonical)
          if provider.respond_to?(:resolve_all)
            provider.resolve_all(canonical_name: canonical)
          else
            provider.resolve(canonical_name: canonical)
          end
        end

        def assemble_composite(provider_results, profile_data, winning_result:, trust_level:, source:)
          aliases = build_aliases(provider_results)
          providers_map = build_providers_map(provider_results, profile_data)

          {
            id:             nil,
            canonical_name: winning_result[:canonical_name],
            kind:           winning_result[:kind] || :human,
            trust:          trust_level,
            source:         source,
            persistent:     true,
            aliases:        aliases,
            groups:         profile_data[:groups],
            profile:        profile_data[:profile],
            providers:      providers_map,
            metadata:       {}
          }
        end

        def build_aliases(provider_results)
          aliases = {}
          provider_results.each do |name, info|
            next unless info[:status] == :resolved && info[:result]

            pi = info[:result][:provider_identity]
            aliases[name] = [pi] if pi
          end
          aliases
        end

        def build_providers_map(provider_results, profile_data)
          providers_map = {}
          provider_results.each do |name, info|
            providers_map[name] = {
              status:      info[:status],
              trust:       info[:trust],
              resolved_at: info[:resolved_at]
            }
          end
          profile_data[:provider_results].each do |name, info|
            providers_map[name] = info
          end
          providers_map
        end

        def bind_and_persist(winning_provider, composite, trust_level)
          Legion::Identity::Process.bind!(winning_provider, composite) if defined?(Legion::Identity::Process)

          if defined?(Legion::Settings) && Legion::Settings.respond_to?(:loader) && Legion::Settings.loader.respond_to?(:settings)
            Legion::Settings.loader.settings[:client] ||= {}
            Legion::Settings.loader.settings[:client][:name] = Legion::Identity::Process.queue_prefix
          end

          persist_to_db(composite)
          persist_identity_json(composite[:canonical_name], composite[:kind]) unless trust_level == :unverified

          @composite.set(composite)
          @resolved.make_true
        end

        def persist_to_db(composite) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          return unless defined?(Legion::Data) && Legion::Data.respond_to?(:connected?) && Legion::Data.connected?
          return unless defined?(Legion::Data::Connection) &&
                        Legion::Data::Connection.respond_to?(:adapter) &&
                        Legion::Data::Connection.adapter == :postgres

          # upsert identity_providers
          composite[:providers]&.each do |name, info|
            Legion::Data.db[:identity_providers].insert_conflict(
              target: :name,
              update: { status: info[:status].to_s, trust_level: info[:trust]&.to_s, last_seen_at: Time.now }
            ).insert(name: name.to_s, status: info[:status].to_s, trust_level: info[:trust]&.to_s, last_seen_at: Time.now)
          end

          # upsert principals
          Legion::Data.db[:principals].insert_conflict(
            target: :canonical_name,
            update: { kind: composite[:kind].to_s, updated_at: Time.now }
          ).insert(
            canonical_name: composite[:canonical_name],
            kind:           composite[:kind].to_s,
            created_at:     Time.now,
            updated_at:     Time.now
          )

          principal_row = Legion::Data.db[:principals].where(canonical_name: composite[:canonical_name]).first
          principal_id = principal_row[:id] if principal_row

          # upsert identities per provider alias
          composite[:aliases]&.each do |provider_name, identities|
            Array(identities).each do |ident|
              Legion::Data.db[:identities].insert_conflict(
                target: %i[principal_id provider_name provider_identity],
                update: { updated_at: Time.now }
              ).insert(
                principal_id:      principal_id,
                provider_name:     provider_name.to_s,
                provider_identity: ident,
                created_at:        Time.now,
                updated_at:        Time.now
              )
            end
          end

          # insert audit log
          Legion::Data.db[:identity_audit_log].insert(
            principal_id:  principal_id,
            event_type:    'identity.resolved',
            provider_name: composite[:source].to_s,
            trust_level:   composite[:trust]&.to_s,
            detail:        Legion::JSON.dump(
              {
                source:     composite[:source],
                trust:      composite[:trust],
                node_id:    composite[:node_id],
                session_id: @session_id
              }
            ),
            node_id:       composite[:node_id],
            session_id:    @session_id,
            created_at:    Time.now
          )
        rescue StandardError => e
          log_warn("DB persistence failed: #{e.message}")
        end

        def persist_identity_json(canonical_name, kind)
          dir = File.expand_path('~/.legionio/settings')
          FileUtils.mkdir_p(dir)
          path = File.join(dir, 'identity.json')
          payload = { canonical_name: canonical_name, kind: kind }
          json = if defined?(Legion::JSON)
                   Legion::JSON.dump(payload)
                 else
                   require 'json'
                   ::JSON.generate(payload)
                 end
          File.write(path, json)
        rescue StandardError => e
          log_warn("identity.json write failed: #{e.message}")
        end

        def handle_canonical_change(old_canonical, new_canonical, _composite)
          if defined?(Legion::Settings) && Legion::Settings.respond_to?(:loader)
            settings = Legion::Settings.loader.settings
            settings[:client] ||= {}
            settings[:client][:name] = new_canonical
          end

          return unless defined?(Legion::Data) && Legion::Data.respond_to?(:connected?) && Legion::Data.connected?
          return unless defined?(Legion::Data::Connection) &&
                        Legion::Data::Connection.respond_to?(:adapter) &&
                        Legion::Data::Connection.adapter == :postgres

          # Audit the canonical change
          old_row = Legion::Data.db[:principals].where(canonical_name: old_canonical).first
          Legion::Data.db[:identity_audit_log].insert(
            principal_id:  old_row&.dig(:id),
            event_type:    'identity.canonical_changed',
            provider_name: '',
            detail:        Legion::JSON.dump({ old: old_canonical, new: new_canonical }),
            created_at:    Time.now
          )
        rescue StandardError => e
          log_warn("canonical change handling failed: #{e.message}")
        end

        def log_warn(message)
          if defined?(Legion::Logging) && Legion::Logging.respond_to?(:warn)
            Legion::Logging.warn("[Identity::Resolver] #{message}")
          else
            $stderr.puts "[Identity::Resolver] #{message}" # rubocop:disable Style/StderrPuts
          end
        end
      end

      # Initialize atomics at module definition time
      @providers  = Concurrent::Array.new
      @composite  = Concurrent::AtomicReference.new(nil)
      @resolved   = Concurrent::AtomicBoolean.new(false)
      @session_id = SecureRandom.uuid
    end
  end
end
