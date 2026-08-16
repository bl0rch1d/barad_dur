class AddEnrichmentToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :technical_notes, :text
    add_column :tickets, :acceptance_criteria, :jsonb, null: false, default: []
  end
end
