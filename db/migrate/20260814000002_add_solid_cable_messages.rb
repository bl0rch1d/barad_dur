# Solid Cable's message table in the primary database, so development (single
# database) can broadcast across processes. Production uses the dedicated
# cable database loaded from db/cable_schema.rb instead.
class AddSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :channel_hash, limit: 8, null: false
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end
