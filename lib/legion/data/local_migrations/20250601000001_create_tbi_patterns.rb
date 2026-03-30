# frozen_string_literal: true

Sequel.migration do
  change do
    create_table?(:tbi_patterns) do
      primary_key :id
      String      :pattern_type,     null: false
      String      :description,      null: false
      String      :tier,             null: false
      # TEXT column holds JSON-encoded behavioral pattern data (up to 64KB)
      String      :pattern_data,     text: true, null: false
      Float       :quality_score,    null: false, default: 0.0
      Integer     :invocation_count, null: false, default: 0
      Float       :success_rate,     null: false, default: 0.0
      # one-way SHA-256 prefix derived from pattern_type+tier+description; not reversible to the submitting instance
      String      :source_hash
      Time        :created_at,       null: false
      Time        :updated_at,       null: false
    end
  end
end
