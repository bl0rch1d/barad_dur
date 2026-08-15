class AddLiveFieldsToRfcs < ActiveRecord::Migration[8.1]
  def change
    change_table :rfcs do |t|
      t.string :job_state, null: false, default: "idle"
      t.string :error
      t.string :progress_note
    end
  end
end
