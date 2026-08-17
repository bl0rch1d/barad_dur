# Spend becomes a ledger instead of a running total.
#
# The old design kept counters (settings.spend_today, agents.cost_today) that
# nothing ever reset, rounded every accrual to whole cents, and updated the
# global one with a read-modify-write that two processes could race. One row
# per charge fixes all of it at once: "today", "per agent", "per phase" and
# "per model" become queries that cannot disagree with each other.
class CreateSpendEntries < ActiveRecord::Migration[8.1]
  def up
    create_table :spend_entries do |t|
      # 4 decimal places: a single agent call often costs a fraction of a cent
      t.decimal :amount, precision: 10, scale: 4, null: false, default: 0
      t.datetime :occurred_at, null: false
      t.string :source, null: false            # phase · chat · rfc · archive · enrich
      t.string :phase                          # for source "phase"
      t.string :ticket_code
      t.string :llm_model
      t.bigint :agent_id
      t.timestamps
    end
    add_index :spend_entries, :occurred_at
    add_index :spend_entries, :ticket_code
    add_index :spend_entries, [:source, :occurred_at]

    # Carry the existing hourly samples over so no money disappears.
    if table_exists?(:spend_samples)
      execute <<~SQL
        INSERT INTO spend_entries (amount, occurred_at, source, created_at, updated_at)
        SELECT amount, bucket, 'legacy', NOW(), NOW()
        FROM spend_samples WHERE amount > 0
      SQL
      drop_table :spend_samples
    end

    # Both counters are derived from the ledger now.
    remove_column :settings, :spend_today if column_exists?(:settings, :spend_today)
    remove_column :agents, :cost_today if column_exists?(:agents, :cost_today)

    # Ticket cost stays as a cache, but with room for sub-cent charges.
    change_column :tickets, :cost, :decimal, precision: 10, scale: 4, default: 0, null: false
    change_column :settings, :spend_cap, :decimal, precision: 10, scale: 2, default: 80, null: false
  end

  def down
    add_column :settings, :spend_today, :decimal, precision: 8, scale: 2, default: 0, null: false
    add_column :agents, :cost_today, :decimal, precision: 8, scale: 2, default: 0, null: false
    create_table :spend_samples do |t|
      t.decimal :amount, precision: 8, scale: 2, null: false, default: 0
      t.datetime :bucket, null: false
      t.timestamps
    end
    add_index :spend_samples, :bucket, unique: true
    drop_table :spend_entries
    change_column :tickets, :cost, :decimal, precision: 8, scale: 2, default: 0, null: false
  end
end
