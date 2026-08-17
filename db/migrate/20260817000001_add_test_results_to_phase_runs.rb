class AddTestResultsToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    change_table :phase_runs do |t|
      t.string :tests_command
      t.integer :tests_passed
      t.integer :tests_failed
    end
  end
end
