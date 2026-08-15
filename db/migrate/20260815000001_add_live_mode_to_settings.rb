class AddLiveModeToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :live_mode, :boolean, null: false, default: false
  end
end
