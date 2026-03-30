# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:consent_maps) do
      primary_key :id
      String  :worker_id,    null: false
      String  :from_tier,    null: false
      String  :to_tier,      null: false
      String  :requested_by, null: false
      String  :state,        null: false, default: 'pending_approval'
      String  :resolved_by
      Time    :resolved_at
      String  :notes,        text: true
      String  :context,      text: true
      Time    :created_at
      Time    :updated_at

      index :worker_id
      index :state
      index %i[worker_id state]
    end
  end
end
