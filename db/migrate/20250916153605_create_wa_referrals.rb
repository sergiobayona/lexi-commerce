class CreateWaReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_referrals do |t|
      t.references :wa_message, null: false, foreign_key: true
      t.string :source_url
      t.string :source_id
      t.string :source_type
      t.text :body
      t.text :headline
      t.string :media_type
      t.string :image_url
      t.string :video_url
      t.string :thumbnail_url
      t.string :ctwa_clid
      t.jsonb :welcome_message_json

      t.timestamps
    end
  end
end
