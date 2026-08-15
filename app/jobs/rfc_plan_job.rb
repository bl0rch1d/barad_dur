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
    targets = Workspace.ticket_targets(setting)
    architect = Agent.find_by(name: "Architect")
    architect&.update!(status: "running", doing: "Planning tickets for the feature request")

    result = HeadlessAgent.call(prompt: RfcPrompts.plan(rfc, targets),
                                chdir: Workspace.root(setting).to_s, max_turns: 20) do |data|
      narrate(rfc, data, "PLAN", "Architect")
    end

    if result.ok
      tickets = Array(StructuredOutput.json_block(result.result_text)&.dig("tickets"))
      proposals = build_proposals(tickets, targets)
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

  def build_proposals(tickets, targets)
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
        "risky" => ticket["risky"] == true || tag == "risky" }
    end
  end
end
