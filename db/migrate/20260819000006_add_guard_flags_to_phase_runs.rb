class AddGuardFlagsToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :guard_flags, :jsonb, null: false, default: []
  end
end
