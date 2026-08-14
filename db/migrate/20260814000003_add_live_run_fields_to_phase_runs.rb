class AddLiveRunFieldsToPhaseRuns < ActiveRecord::Migration[8.1]
  def change
    change_table :phase_runs do |t|
      t.string :runner, null: false, default: "demo"
      t.text :log
      t.integer :exit_status
      t.decimal :cost, precision: 8, scale: 4, null: false, default: 0
      t.string :session_id
    end
  end
end
