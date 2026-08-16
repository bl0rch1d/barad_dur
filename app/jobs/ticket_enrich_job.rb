# One-off backfill for tickets that predate rich grooming: a short agent
# pass reads the workspace and produces summary / technical notes /
# acceptance criteria. Progress marker lives in Setting.setup["enrich:<code>"].
class TicketEnrichJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    setting = Setting.instance
    harness = Harness.active?(setting) ? Harness.detect(setting) : nil
    chdir = Workspace.repo_path(ticket.repo) || harness&.path || Workspace.root(setting).to_s

    result = HeadlessAgent.call(prompt: prompt_for(ticket), chdir: chdir, max_turns: 12,
                                extra_args: ["--add-dir", Workspace.root(setting).to_s])

    if result.ok && (data = StructuredOutput.json_block(result.result_text))
      ClaudeCodeRunner.apply_enrichment(ticket, data.merge("summary" => data["summary"]))
      Event.record!(phase_tag: "PLAN", ticket: ticket, agent_name: "Architect",
                    meta: "enriched", text: "#{ticket.code} enriched — summary and acceptance criteria added")
    else
      Event.record!(phase_tag: "PLAN", tone: "var(--err)", ticket: ticket, agent_name: "Architect",
                    text: "Enrichment failed for #{ticket.code}: #{(result.error || 'no parseable output').to_s.truncate(120)}")
    end
  ensure
    setting = Setting.instance.reload
    setting.update!(setup: setting.setup.except("enrich:#{ticket&.code}"))
    PipelineEngine.broadcast
  end

  private

  def prompt_for(ticket)
    <<~TXT
      You are the Architect agent of an automated SDLC pipeline. Read the
      relevant parts of this repository and produce a concise brief for the
      ticket below. Do NOT modify any files.

      Ticket #{ticket.code}: "#{ticket.title}" (repo #{ticket.repo}, state #{ticket.state})
      #{"Existing description: #{ticket.description}\n" if ticket.description.present?}
      #{"Openspec change: #{PhasePrompts.change_ref(ticket)}\n" if PhasePrompts.change_ref(ticket)}
      End your FINAL message with only a fenced json block:
      ```json
      {"summary": "2-3 sentences on what this ticket delivers and why",
       "technical_notes": "key files, approach, risks — short paragraph",
       "acceptance_criteria": ["verifiable outcome 1", "verifiable outcome 2"]}
      ```
    TXT
  end
end
