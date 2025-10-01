class CreateWaErrors < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_errors do |t|
      # Error classification
      t.string :error_type, null: false # 'system', 'message', 'status'
      t.string :error_level, null: false # 'error', 'warning', 'info'

      # Error details
      t.integer :error_code
      t.string :error_title
      t.text :error_message
      t.text :error_details

      # Context
      t.string :provider_message_id # For message and status errors
      t.bigint :wa_message_id # Link to wa_message if exists
      t.bigint :webhook_event_id # Link to webhook event

      # Raw error data
      t.jsonb :raw_error_data, default: {}, null: false

      # Metadata
      t.boolean :resolved, default: false
      t.text :resolution_notes
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :wa_errors, :error_type
    add_index :wa_errors, :error_level
    add_index :wa_errors, :error_code
    add_index :wa_errors, :provider_message_id
    add_index :wa_errors, :wa_message_id
    add_index :wa_errors, :webhook_event_id
    add_index :wa_errors, :resolved
    add_index :wa_errors, :created_at
    add_index :wa_errors, :raw_error_data, using: :gin

    add_foreign_key :wa_errors, :wa_messages, column: :wa_message_id, on_delete: :nullify
    add_foreign_key :wa_errors, :webhook_events, column: :webhook_event_id, on_delete: :nullify
  end
end
