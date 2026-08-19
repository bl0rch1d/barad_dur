# The pull request is part of a ticket's identity now that opening one is the
# default way work lands — a link in an artifacts string is not enough to
# render it, or to merge it later.
class AddPrUrlToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :pr_url, :string
    # carry over anything the manual button already recorded
    execute <<~SQL
      UPDATE tickets SET pr_url = substring(artifact FROM 'https://[^"[:space:]]+')
      FROM (SELECT id AS t_id, jsonb_array_elements_text(artifacts) AS artifact FROM tickets) a
      WHERE tickets.id = a.t_id AND a.artifact LIKE 'PR: http%'
    SQL
  end

  def down
    remove_column :tickets, :pr_url
  end
end
