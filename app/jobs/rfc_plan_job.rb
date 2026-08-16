# Runs a real Architect planning pass over the investigation + the user's
# answers, producing ordered ticket proposals ready to push to the board.
class RfcPlanJob < RfcAgentJob
  TONES = {
    "risky" => "var(--err)", "tests" => "var(--warn)", "schema" => "var(--info)",
    "api" => "var(--info)", "docs" => "var(--tx3)"
  }.freeze

  def perform(rfc_id)
    rfc = Rfc.find_by(id: rfc_id)
    return unless rfc && rfc.job_state == "planning"

    setting = Setting.instance
    targets = Workspace.selected_ticket_targets(setting).presence || Workspace.ticket_targets(setting)
    architect = Agent.for_phase("planning")
    architect&.update!(status: "running", doing: "Planning tickets for the feature request")

    invocation = Harness.phase_invocation("planning", setting)
    agents = Harness.phase_agents("planning", setting)
    Event.record!(phase_tag: "PLAN", agent_name: "Architect", ticket_code: "RFC",
                  meta: invocation ? "harness" : "built-in",
                  text: "Planning started via #{invocation || 'built-in Architect prompt'}" \
                        "#{" · delegable agents: #{agents.join(', ')}" if agents.any?}")
    PipelineEngine.broadcast

    context = execution_context(setting)
    result = HeadlessAgent.call(prompt: RfcPrompts.plan(rfc, targets, setting),
                                chdir: context[:chdir], extra_args: context[:extra_args],
                                max_turns: 30) do |data|
      narrate(rfc, data, "PLAN", "Architect")
    end

    if result.ok
      data = StructuredOutput.json_block(result.result_text) || {}
      tickets = Array(data["tickets"])
      change = data["change"].to_s.parameterize.presence
      proposals = build_proposals(tickets, targets, change)
      if proposals.any?
        rfc.update!(proposals: proposals, stage: 3, job_state: "idle",
                    error: nil, progress_note: nil, pushed: false)
        accrue(result, "Architect")
        Event.record!(phase_tag: "PLAN", agent_name: "Architect", ticket_code: "RFC", meta: run_meta(result),
                      text: "Plan ready — #{proposals.size} tickets in dependency order")
      else
        fail_rfc(rfc, "PLAN", "Architect", "planner returned no parseable tickets")
      end
    else
      fail_rfc(rfc, "PLAN", "Architect", result.error)
    end
    architect&.update!(status: "idle", doing: "Last: planned feature request tickets")
    PipelineEngine.broadcast
  end

  private

  def build_proposals(tickets, targets, change = nil)
    tickets.first(6).each_with_index.filter_map do |ticket, index|
      title = ticket["title"].to_s.strip
      next if title.blank?

      repo = targets.include?(ticket["repo"]) ? ticket["repo"] : targets.first
      tag = ticket["tag"].to_s.presence || "core"
      deps = Array(ticket["depends_on"]).map(&:to_i).select { |d| d.between?(1, index) }

      { "step" => (index + 1).to_s, "title" => title.truncate(120), "repo" => repo,
        "dep" => deps.any? ? "needs #{deps.join(', ')}" : "no deps",
        "dep_indexes" => deps, "est" => ticket["estimate"].to_s.presence || "?",
        "tag" => tag, "tone" => TONES.fetch(tag, "var(--accent)"),
        "risky" => ticket["risky"] == true || tag == "risky",
        "summary" => ticket["summary"].to_s.strip.truncate(1200).presence,
        "acceptance_criteria" => Array(ticket["acceptance_criteria"]).map { |c| c.to_s.strip.truncate(200) }.reject(&:blank?).first(8),
        "change" => change }.compact
    end
  end
end
