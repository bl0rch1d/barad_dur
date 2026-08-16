# Board redesign: inserts the ready_to_implement state (4) between planning
# and implementation, renames backlog→draft (label only — int 0 unchanged),
# and adds a free-form description for draft tickets. Existing state ints and
# pending gate targets shift up by one from implementation onward.
class AddDraftPipelineStates < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :description, :text
    execute "UPDATE tickets SET state = state + 1 WHERE state >= 4"
    execute "UPDATE gates SET to_state = to_state + 1 WHERE to_state >= 4"
  end

  def down
    execute "UPDATE gates SET to_state = to_state - 1 WHERE to_state >= 5"
    execute "UPDATE tickets SET state = state - 1 WHERE state >= 5"
    remove_column :tickets, :description
  end
end
