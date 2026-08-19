# The testing phase runs linters, unit, regression and e2e suites where they
# exist. One pass/fail pair cannot say which of those actually ran, so keep
# the per-suite breakdown alongside the totals.
class AddTestSuitesToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :test_suites, :jsonb, null: false, default: []
  end
end
