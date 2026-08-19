class AgentsController < ApplicationController
  before_action :require_realm!, only: :index
  def index
    @agents = Agent.ordered.to_a
    @total_cost = @agents.sum(&:cost_today)
    @harness = Harness.detect(@setting)
    # only claim a harness roster when the mapping has actually been applied
    @harness = nil unless @harness && (@agents.map(&:name) & @harness.agents).any?
    @specialists = @harness ? AgentRoster.specialists(@setting) : []
  end

  # Pin an agent to a model, or clear the pin so it follows the realm again.
  def model
    agent = Agent.find(params[:id])
    value = params[:model].to_s
    if value.blank?
      agent.update!(model_id: nil)
    elsif Setting::ORCHESTRATOR_MODELS.key?(value)
      agent.update!(model_id: value)
    end
    Event.record!(phase_tag: "SYS", agent_name: "you",
                  text: "#{agent.name} now runs on #{agent.reload.model_label}" \
                        "#{' (following the realm)' unless agent.pinned?}")
    PipelineEngine.broadcast
    back
  end
end
