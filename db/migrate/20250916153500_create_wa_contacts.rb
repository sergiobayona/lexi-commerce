class CreateWaContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_contacts do |t|
      t.string :wa_id
      t.string :profile_name
      t.string :identity_key_hash
      t.datetime :identity_last_changed_at
      t.datetime :first_seen_at
      t.datetime :last_seen_at

      t.timestamps
    end
    add_index :wa_contacts, :wa_id, unique: true
  end
end
