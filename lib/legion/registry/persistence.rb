# frozen_string_literal: true

module Legion
  module Registry
    module Persistence
      class << self
        def data_available?
          return false unless defined?(Legion::Data)
          return false unless Legion::Data.respond_to?(:connection) && Legion::Data.connection

          Legion::Data.connection.table_exists?(:extensions_registry)
        rescue StandardError => e
          Legion::Logging.debug "Registry::Persistence#data_available? check failed: #{e.message}" if defined?(Legion::Logging)
          false
        end

        def load_from_db
          return 0 unless data_available?

          count = 0
          registry_dataset.each do |row|
            entry = Entry.new(
              name:        row[:name],
              version:     row[:version],
              author:      row[:author],
              description: row[:description],
              status:      row[:status]&.to_sym,
              airb_status: row[:airb_status],
              risk_tier:   row[:risk_tier]
            )
            Legion::Registry.register(entry)
            count += 1
          end
          count
        end

        def persist(entry)
          return false unless data_available?

          attrs = persistence_attrs(entry)
          existing = registry_dataset.where(name: entry.name).first

          if existing
            registry_dataset.where(name: entry.name).update(**attrs, updated_at: Time.now)
          else
            registry_dataset.insert(**attrs, created_at: Time.now, updated_at: Time.now)
          end

          true
        rescue StandardError => e
          Legion::Logging.warn("Registry::Persistence failed to persist #{entry.name}: #{e.message}") if defined?(Legion::Logging)
          false
        end

        private

        def registry_dataset
          Legion::Data.connection[:extensions_registry]
        end

        def persistence_attrs(entry)
          parts = entry.name.to_s.split('-')
          mod_name = parts.map(&:capitalize).join('::')

          {
            name:        entry.name,
            module_name: mod_name,
            status:      entry.status.to_s,
            description: entry.description
          }
        end
      end
    end
  end
end
