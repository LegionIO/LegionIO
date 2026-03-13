# frozen_string_literal: true

require 'sequel/extensions/migration'

module Legion
  module Extensions
    module Data
      class Migrator < Sequel::IntegerMigrator
        def initialize(path, extension, lex_name, **)
          @path = path
          @extension = extension
          @lex_name = lex_name
          schema_dataset
          super(Legion::Data::Connection.sequel, path)
        end

        def default_schema_column
          :schema_version
        end

        def default_schema_table
          :extensions
        end

        def schema_dataset
          dataset = Legion::Data::Connection.sequel.from(default_schema_table).where(namespace: @extension)
          return dataset if dataset.any?

          Legion::Data::Model::Extension.insert(active: 1, namespace: @extension, name: @lex_name)
          Legion::Data::Connection.sequel.from(default_schema_table).where(namespace: @extension)
        end
        alias ds schema_dataset
      end
    end
  end
end
