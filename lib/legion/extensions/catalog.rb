# frozen_string_literal: true

require_relative 'catalog/registry'

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
          @extension_catalog_available = nil
          @extension_catalog_connection_id = nil
          @warned_missing_extension_catalog = false
        end

        private

        def entries
          @entries ||= {}
        end

        def publish_transition(lex_name, new_state)
          return unless defined?(Legion::Transport::Connection) &&
                        Legion::Transport::Connection.respond_to?(:session_open?) &&
                        Legion::Transport::Connection.session_open?

          payload = Legion::JSON.dump(
            lex_name:  lex_name,
            state:     new_state.to_s,
            timestamp: Time.now.to_i
          )

          exchange = Legion::Transport::Exchange.new('legion.catalog')
          exchange.publish(payload, routing_key: "legion.catalog.#{lex_name}.#{new_state}",
                                    content_type: 'application/json', persistent: true)
        rescue StandardError => e
          Legion::Logging.warn { "Catalog publish failed for #{lex_name}=#{new_state}: #{e.class}: #{e.message}" } if defined?(Legion::Logging)
        end

        def persist_transition(lex_name, new_state)
          return unless defined?(Legion::Data::Local) &&
                        Legion::Data::Local.respond_to?(:connected?) &&
                        Legion::Data::Local.connected?

          ensure_local_migration_registered!
          return warn_missing_extension_catalog_once unless extension_catalog_table_available?

          model = Legion::Data::Local.model(:extension_catalog)
          existing = model.where(lex_name: lex_name).first
          if existing
            existing.update(state: new_state.to_s, updated_at: Time.now)
          else
            model.insert(lex_name: lex_name, state: new_state.to_s, created_at: Time.now, updated_at: Time.now)
          end
        rescue StandardError => e
          Legion::Logging.warn { "Catalog persist failed for #{lex_name}=#{new_state}: #{e.class}: #{e.message}" } if defined?(Legion::Logging)
        end

        def extension_catalog_table_available?
          connection = Legion::Data::Local.connection
          return false unless connection

          connection_id = connection.object_id
          return true if @extension_catalog_connection_id == connection_id && @extension_catalog_available == true

          available =
            if connection.respond_to?(:tables)
              connection.tables.include?(:extension_catalog)
            else
              connection.respond_to?(:table_exists?) && connection.table_exists?(:extension_catalog)
            end

          if available
            @extension_catalog_connection_id = connection_id
            @extension_catalog_available = true
          else
            @extension_catalog_connection_id = nil if @extension_catalog_connection_id == connection_id
            @extension_catalog_available = nil
          end

          available
        rescue StandardError => e
          Legion::Logging.warn { "Catalog table availability check failed: #{e.class}: #{e.message}" } if defined?(Legion::Logging)
          false
        end

        def ensure_local_migration_registered!
          return unless defined?(Legion::Data::Local) &&
                        Legion::Data::Local.respond_to?(:register_migrations)

          path = extension_catalog_migrations_path
          return unless Dir.exist?(path)

          registered = if Legion::Data::Local.respond_to?(:registered_migrations)
                         Legion::Data::Local.registered_migrations
                       else
                         {}
                       end
          return if registered.is_a?(Hash) && registered.key?(:extension_catalog)

          Legion::Data::Local.register_migrations(name: :extension_catalog, path: path)
        rescue StandardError => e
          Legion::Logging.warn { "Catalog migration registration failed: #{e.class}: #{e.message}" } if defined?(Legion::Logging)
        end

        def extension_catalog_migrations_path
          File.expand_path('../data/local_migrations', __dir__)
        end

        def warn_missing_extension_catalog_once
          return false if @warned_missing_extension_catalog

          @warned_missing_extension_catalog = true
          Legion::Logging.warn('Catalog persist skipped: extension_catalog table is missing in Legion::Data::Local') if defined?(Legion::Logging)
          false
        end
      end

      send(:ensure_local_migration_registered!) if defined?(Legion::Data::Local)
    end
  end
end
