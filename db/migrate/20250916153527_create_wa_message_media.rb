class CreateWaMessageMedia < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_message_media do |t|
      t.references :wa_message, null: false, foreign_key: true
      t.references :wa_media, null: false, foreign_key: true
      t.string :purpose

      t.timestamps
    end
  end
end
