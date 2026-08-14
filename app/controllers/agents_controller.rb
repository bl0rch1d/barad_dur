class AgentsController < ApplicationController
  def index
    @agents = Agent.ordered.to_a
    @total_cost = @agents.sum(&:cost_today)
  end
end
