# Demo mode is gone: the app is always live. Tick-driven simulation columns
# and the demo-only CI table go with it.
class PurgeDemoMode < ActiveRecord::Migration[8.1]
  def up
    remove_column :settings, :live_mode
    remove_column :settings, :tick_count
    remove_column :tickets, :phase_progress
    drop_table :ci_suites
  end

  def down
    add_column :settings, :live_mode, :boolean, null: false, default: false
    add_column :settings, :tick_count, :integer, null: false, default: 0
    add_column :tickets, :phase_progress, :integer, null: false, default: 0
    create_table :ci_suites do |t|
      t.string :name, null: false
      t.integer :pct, null: false, default: 100
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
