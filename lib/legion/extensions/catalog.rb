# frozen_string_literal: true

module Legion
  module Extensions
    module Catalog
      STATES = %i[registered loaded starting running stopping stopped].freeze
      STATE_ORDER = STATES.each_with_index.to_h.freeze

      class << self
        def register(lex_name, state: :registered)
          return if @entries&.key?(lex_name)

          entries[lex_name] = {
            state:         state,
            registered_at: Time.now,
            started_at:    nil,
            stopped_at:    nil
          }
        end

        def transition(lex_name, new_state)
          return unless entries.key?(lex_name)

          entries[lex_name][:state] = new_state
          entries[lex_name][:started_at] = Time.now if new_state == :running
          entries[lex_name][:stopped_at] = Time.now if new_state == :stopped

          publish_transition(lex_name, new_state)
          persist_transition(lex_name, new_state)
        end

        def state(lex_name)
          entries.dig(lex_name, :state)
        end

        def entry(lex_name)
          entries[lex_name]
        end

        def loaded?(lex_name)
          s = state(lex_name)
          return false unless s

          STATE_ORDER[s] >= STATE_ORDER[:loaded]
        end

        def running?(lex_name)
          state(lex_name) == :running
        end

        def all
          entries.dup
        end

        def reset!
          @entries = {}
        end

        private

        def entries
          @entries ||= {}
        end

        def publish_transition(lex_name, new_state)
          return unless defined?(Legion::Transport::Connection) &&
                        Legion::Transport::Connection.respond_to?(:session_open?) &&
                        Legion::Transport::Connection.session_open?

          Legion::Transport::Messages::Dynamic.new(
            function:    'catalog_transition',
            routing_key: "legion.catalog.#{lex_name}.#{new_state}",
            args:        { lex_name: lex_name, state: new_state.to_s, timestamp: Time.now.to_i }
          ).publish
        rescue StandardError => e
          Legion::Logging.debug { "Catalog publish failed: #{e.message}" } if defined?(Legion::Logging)
        end

        def persist_transition(lex_name, new_state)
          return unless defined?(Legion::Data::Local) &&
                        Legion::Data::Local.respond_to?(:connected?) &&
                        Legion::Data::Local.connected?

          model = Legion::Data::Local.model(:extension_catalog)
          existing = model.where(lex_name: lex_name).first
          if existing
            existing.update(state: new_state.to_s, updated_at: Time.now)
          else
            model.insert(lex_name: lex_name, state: new_state.to_s, created_at: Time.now, updated_at: Time.now)
          end
        rescue StandardError => e
          Legion::Logging.debug { "Catalog persist failed: #{e.message}" } if defined?(Legion::Logging)
        end
      end

      if defined?(Legion::Data::Local)
        migrations_path = File.expand_path('../../data/local_migrations', __dir__)
        Legion::Data::Local.register_migrations(name: :extension_catalog, path: migrations_path) if Dir.exist?(migrations_path)
      end
    end
  end
end
