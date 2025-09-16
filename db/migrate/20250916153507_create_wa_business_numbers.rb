class CreateWaBusinessNumbers < ActiveRecord::Migration[8.0]
  def change
    create_table :wa_business_numbers do |t|
      t.string :phone_number_id
      t.string :display_phone_number

      t.timestamps
    end
    add_index :wa_business_numbers, :phone_number_id, unique: true
  end
end
