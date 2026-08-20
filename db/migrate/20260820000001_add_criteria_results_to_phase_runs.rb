class AddCriteriaResultsToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :criteria_results, :jsonb, null: false, default: []
    add_column :phase_runs, :deviations, :jsonb, null: false, default: []
  end
end
