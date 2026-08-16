class BoardController < ApplicationController
  # Column order; Blocked is a derived overlay — a blocked ticket appears
  # there (with its subtype) instead of in its phase column, and returns
  # automatically once the blocker clears.
  COLUMNS = %w[draft ready investigation planning ready_to_implement blocked
               implementation review testing deployment].freeze

  def show
    @shipped_view = params[:shipped] == "1"
    @shipped = @shipped_view ? Ticket.done.order(finished_at: :desc, id: :desc).limit(50).to_a : []
    @shipped_count = Ticket.done.count

    tickets = Ticket.on_board.includes(:agent, :phase_runs, :ticket_gates).order(:code).to_a

    @repo_options = tickets.map { |t| t.repo.to_s.split("·").first.to_s.strip }.uniq.sort
    @repo_filter = @repo_options.include?(params[:repo]) ? params[:repo] : nil
    @blocked_only = params[:blocked] == "1"
    tickets = tickets.select { |t| t.repo.to_s.start_with?(@repo_filter) } if @repo_filter

    blocked, active = tickets.partition { |t| t.blocker.present? }
    active = [] if @blocked_only
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
