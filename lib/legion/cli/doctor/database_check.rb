# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class DatabaseCheck
        def name
          'Database'
        end

        def run
          adapter, database = read_db_config
          return Result.new(name: name, status: :skip, message: 'No database configured') if adapter.nil?

          check_database(adapter, database)
        rescue StandardError => e
          Result.new(
            name:         name,
            status:       :fail,
            message:      "Database check error: #{e.message}",
            prescription: 'Check database configuration in settings'
          )
        end

        private

        def read_db_config
          return [nil, nil] unless defined?(Legion::Settings)

          data = Legion::Settings[:data]
          return [nil, nil] unless data.is_a?(Hash) && data[:adapter]

          [data[:adapter].to_s, data[:database].to_s]
        rescue StandardError => e
          Legion::Logging.warn("DatabaseCheck#read_db_config failed: #{e.message}") if defined?(Legion::Logging)
          [nil, nil]
        end

        def check_database(adapter, database)
          case adapter
          when 'sqlite', 'sqlite3'
            check_sqlite(database)
          when 'postgresql', 'postgres', 'mysql2', 'mysql'
            check_network_db(adapter, database)
          else
            Result.new(name: name, status: :skip, message: "Unknown adapter: #{adapter}")
          end
        end

        def check_sqlite(database)
          if database.nil? || database.empty?
            return Result.new(
              name:         name,
              status:       :warn,
              message:      'SQLite database path not configured',
              prescription: 'Set data.database in settings'
            )
          end

          db_path = File.expand_path(database)
          dir = File.dirname(db_path)
          if File.exist?(db_path)
            Result.new(name: name, status: :pass, message: "SQLite file exists: #{db_path}")
          elsif Dir.exist?(dir)
            Result.new(name: name, status: :pass, message: "SQLite dir writable: #{dir}")
          else
            Result.new(
              name:         name,
              status:       :fail,
              message:      "SQLite database directory missing: #{dir}",
              prescription: "Create directory: `mkdir -p #{dir}`"
            )
          end
        end

        def check_network_db(adapter, _database)
          require 'legion/data'
          Legion::Data.setup
          Result.new(name: name, status: :pass, message: "#{adapter} connection ok")
        rescue LoadError
          Result.new(name: name, status: :skip, message: 'legion-data not installed')
        rescue StandardError => e
          Result.new(
            name:         name,
            status:       :fail,
            message:      "#{adapter} connection failed: #{e.message}",
            prescription: 'Check database configuration in settings'
          )
        end
      end
    end
  end
end
