# Runs a real read-only Scout investigation of the workspace for a feature
# request, producing the trace and clarifying questions the RFC screen shows.
class RfcInvestigateJob < RfcAgentJob
  def perform(rfc_id)
    rfc = Rfc.find_by(id: rfc_id)
    return unless rfc && rfc.job_state == "investigating"

    setting = Setting.instance
    targets = Workspace.ticket_targets(setting)
    scout = Agent.find_by(name: "Scout")
    scout&.update!(status: "running", doing: "Investigating feature request in the workspace")

    context = execution_context(setting)
    result = HeadlessAgent.call(prompt: RfcPrompts.investigate(rfc, targets, setting),
                                chdir: context[:chdir], extra_args: context[:extra_args],
                                max_turns: 30) do |data|
      narrate(rfc, data, "INVEST", "Scout")
    end

    if result.ok
      data = StructuredOutput.json_block(result.result_text) || {}
      trace = parse_trace(data, result)
      questions = parse_questions(data)
      rfc.update!(trace: trace, questions: questions, stage: 2,
                  job_state: "idle", error: nil, progress_note: nil)
      accrue(result, "Scout")
      Event.record!(phase_tag: "INVEST", agent_name: "Scout", ticket_code: "RFC", meta: run_meta(result),
                    text: "Investigation complete — #{trace.size} findings, #{questions.size} questions")
    else
      fail_rfc(rfc, "INVEST", "Scout", result.error)
    end
    scout&.update!(status: "idle", doing: "Last: investigated a feature request")
    PipelineEngine.broadcast
  end

  private

  def parse_trace(data, result)
    trace = Array(data["trace"]).first(10).filter_map do |item|
      next if item["text"].blank?

      warn = item["mark"].to_s == "!"
      { "mark" => warn ? "!" : "✓", "tone" => warn ? "var(--warn)" : "var(--ok)",
        "text" => item["text"].to_s.truncate(180) }
    end
    return trace if trace.any?

    [{ "mark" => "✓", "tone" => "var(--ok)",
       "text" => result.result_text.to_s.gsub(/\s+/, " ").truncate(180) }]
  end

  def parse_questions(data)
    Array(data["questions"]).first(3).each_with_index.filter_map do |question, index|
      next if question["q"].blank?

      opts = Array(question["opts"]).first(4).map { |o| o.to_s.truncate(40) }
      next if opts.size < 2

      { "key" => "q#{index + 1}", "q" => question["q"].to_s.truncate(200),
        "why" => question["why"].to_s.truncate(120), "opts" => opts }
    end
  end
end
