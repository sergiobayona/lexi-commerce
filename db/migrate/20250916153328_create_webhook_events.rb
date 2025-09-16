class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.string :provider, null: false, comment: "e.g. 'whatsapp'"
      t.string :object_name, comment: "top-level 'object' field from the webhook"
      t.jsonb  :payload, null: false, default: {}

      t.timestamps
    end

    add_index :webhook_events, :created_at
    add_index :webhook_events, :provider
    add_index :webhook_events, :payload, using: :gin  # optional, for ad-hoc JSONB queries
  end
end
