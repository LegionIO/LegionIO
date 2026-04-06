# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:tool_embedding_cache) do
      primary_key :id
      String :content_hash, size: 32, null: false
      String :model, null: false
      String :tool_name, null: false
      String :vector, text: true, null: false
      Time :embedded_at, null: false
      unique %i[content_hash model]
    end
  end
end
