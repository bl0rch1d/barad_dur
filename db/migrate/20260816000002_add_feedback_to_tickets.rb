class AddFeedbackToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :feedback, :text
  end
end
