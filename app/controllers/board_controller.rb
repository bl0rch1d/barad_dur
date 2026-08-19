class BoardController < ApplicationController
  before_action :require_realm!, only: :show
  # Column order; Blocked is a derived overlay — a blocked ticket appears
  # there (with its subtype) instead of in its phase column, and returns
  # automatically once the blocker clears.
  COLUMNS = %w[draft ready investigation planning ready_to_implement blocked
               implementation review testing deployment done].freeze

  # Done accumulates forever; the column shows the latest landings and points
  # at the full history rather than growing without limit.
  DONE_ON_BOARD = 8

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

    recent_done = Ticket.done.order(finished_at: :desc, id: :desc).limit(DONE_ON_BOARD).to_a
    recent_done = recent_done.select { |t| t.repo.to_s.start_with?(@repo_filter) } if @repo_filter
    recent_done = [] if @blocked_only

    @columns = COLUMNS.map do |column|
      if column == "blocked"
        { state: "blocked", name: "Blocked", tone: "var(--err)", tickets: blocked, blocked: true }
      elsif column == "done"
        { state: "done", name: "Done", tone: "var(--ok)", tickets: recent_done, done: true }
      else
        meta = helpers.state_meta(column)
        { state: column, name: meta[:name], tone: meta[:tone], tickets: by_state.fetch(column, []) }
      end
    end
    @running_count = Ticket.in_flight.count
  end
end
