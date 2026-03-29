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
      # anonymous fingerprint-safe hash of the contributing instance
      String      :source_hash
      DateTime    :created_at,       null: false
      DateTime    :updated_at,       null: false
    end
  end
end
