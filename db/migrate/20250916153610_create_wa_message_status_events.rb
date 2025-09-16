class CreateWaMessageStatusEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_message_status_events do |t|
      t.string :provider_message_id
      t.string :event_type
      t.datetime :event_timestamp
      t.jsonb :raw

      t.timestamps
    end
  end
end
