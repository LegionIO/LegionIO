# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:extension_catalog) do
      primary_key :id
      String :lex_name, null: false, unique: true
      String :state, null: false, default: 'registered'
      Time :created_at
      Time :updated_at
      Time :started_at
      Time :stopped_at
    end
  end
end
