class DropOutboxEvents < ActiveRecord::Migration[8.0]
  def change
    drop_table :outbox_events, if_exists: true
  end
end
