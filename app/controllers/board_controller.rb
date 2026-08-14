class BoardController < ApplicationController
  def show
    tickets = Ticket.on_board.includes(:agent).order(:code).group_by(&:state)
    @columns = Ticket::STATES.keys.reject { |s| s == :done }.map do |state|
      meta = helpers.state_meta(state)
      { state: state.to_s, name: meta[:name], tone: meta[:tone], tickets: tickets.fetch(state.to_s, []) }
    end
    @running_count = Ticket.in_flight.count
  end
end
