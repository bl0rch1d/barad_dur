class AddReviewFindingsToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :phase_runs, :review_findings, :jsonb, null: false, default: []
    add_column :phase_runs, :review_verdict, :string
  end
end
