class AgentsController < ApplicationController
  def index
    @agents = Agent.ordered.to_a
    @total_cost = @agents.sum(&:cost_today)
    @harness = Harness.detect(@setting)
    # only claim a harness roster when the mapping has actually been applied
    @harness = nil unless @harness && (@agents.map(&:name) & @harness.agents).any?
    @specialists = @harness ? AgentRoster.specialists(@setting) : []
  end
end
