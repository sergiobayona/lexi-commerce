class CreateWaMedia < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_media do |t|
      t.string :provider_media_id
      t.string :sha256
      t.string :mime_type
      t.boolean :is_voice
      t.bigint :bytes
      t.string :storage_url
      t.string :download_status
      t.text :last_error

      t.timestamps
    end
    add_index :wa_media, :provider_media_id, unique: true
    add_index :wa_media, :sha256, unique: true
  end
end
