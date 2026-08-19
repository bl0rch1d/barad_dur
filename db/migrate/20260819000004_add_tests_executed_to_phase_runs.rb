# "No suite ran" used to be indistinguishable from "the suite passed": with no
# counts reported the run recorded nothing, tests_failed? was false, and a
# pull request opened as though the work had been verified.
class AddTestsExecutedToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :tests_executed, :boolean, null: false, default: false
    # anything that already reported counts did run something
    reversible do |dir|
      dir.up { execute "UPDATE phase_runs SET tests_executed = true WHERE tests_passed IS NOT NULL OR tests_failed IS NOT NULL" }
    end
  end
end
