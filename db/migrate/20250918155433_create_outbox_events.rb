class CreateOutboxEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :outbox_events do |t|
      t.string :event_type, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :status, default: "pending", null: false
      t.string :idempotency_key, null: false
      t.datetime :processed_at
      t.integer :retry_count, default: 0, null: false
      t.text :last_error

      t.timestamps

      t.index :event_type
      t.index :status
      t.index :idempotency_key, unique: true
      t.index [:created_at, :status]
      t.index :payload, using: :gin
    end
  end
end
