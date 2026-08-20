class AddBudgetToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :budget, :jsonb, null: false, default: {}
  end
end
