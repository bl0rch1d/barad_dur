class AgentsController < ApplicationController
  def index
    @agents = Agent.ordered.to_a
    @total_cost = @agents.sum(&:cost_today)
    @harness = @setting.live_mode? ? Harness.detect(@setting) : nil
    @specialists = @harness ? AgentRoster.specialists(@setting) : []
  end
end
