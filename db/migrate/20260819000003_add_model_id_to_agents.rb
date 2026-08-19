# Each agent may run on its own model. Null means "follow the realm's
# orchestrator setting", so changing that still moves every agent that has not
# been pinned — which is what most realms want.
class AddModelIdToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :model_id, :string
  end
end
