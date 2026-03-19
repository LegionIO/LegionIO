# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:extension_permissions) do
      primary_key :id
      String :lex_name, null: false
      String :path, null: false
      String :access_type, null: false
      TrueClass :approved, default: false
      Time :created_at
      Time :updated_at

      index %i[lex_name path access_type], unique: true
    end
  end
end
