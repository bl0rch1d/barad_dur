class BoardController < ApplicationController
  # Column order; Blocked is a derived overlay — a blocked ticket appears
  # there (with its subtype) instead of in its phase column, and returns
  # automatically once the blocker clears.
  COLUMNS = %w[draft ready investigation planning ready_to_implement blocked
               implementation review testing deployment].freeze

  def show
    tickets = Ticket.on_board.includes(:agent, :phase_runs, :ticket_gates).order(:code).to_a
    blocked, active = tickets.partition { |t| t.blocker.present? }
    by_state = active.group_by(&:state)

    @columns = COLUMNS.map do |column|
      if column == "blocked"
        { state: "blocked", name: "Blocked", tone: "var(--err)", tickets: blocked, blocked: true }
      else
        meta = helpers.state_meta(column)
        { state: column, name: meta[:name], tone: meta[:tone], tickets: by_state.fetch(column, []) }
      end
    end
    @running_count = Ticket.in_flight.count
  end
end
