class CreateWaMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_messages do |t|
      t.string :provider_message_id, null: false
      t.string :direction
      t.references :wa_contact, null: false, foreign_key: true
      t.references :wa_business_number, null: false, foreign_key: true
      t.string :type_name
      t.text :body_text
      t.datetime :timestamp
      t.string :status, default: 'received'
      t.string :context_msg_id
      t.boolean :has_media, default: false
      t.string :media_kind
      t.jsonb :wa_contact_snapshot
      t.jsonb :metadata_snapshot
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end
    add_index :wa_messages, :provider_message_id, unique: true
  end
end
