# After a merge, the applied openspec change is archived into the permanent
# spec tree via the harness's own command (e.g. /opsx:archive) — completing
# the openspec lifecycle. No-ops when the ticket has no change ref or the
# harness offers no archive command.
class ArchiveChangeJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    change = PhasePrompts.change_ref(ticket)
    return unless change

    setting = Setting.instance
    harness = Harness.active?(setting) ? Harness.detect(setting) : nil
    return unless harness && Harness.provides?(harness, "opsx:archive")

    Event.record!(phase_tag: "SPEC", ticket: ticket, agent_name: "Shipper",
                  meta: "harness", text: "Archiving change #{change} via /opsx:archive")

    prompt = <<~TXT
      /opsx:archive #{change}

      Pipeline context: you are running non-interactively after ticket
      #{ticket.code} ("#{ticket.title}") was merged. Archive the applied
      change into the permanent spec tree and commit the result with a clear
      message. Never ask the user questions.
    TXT
    result = HeadlessAgent.call(prompt: prompt, chdir: harness.path, max_turns: 20,
                                extra_args: ["--add-dir", Workspace.root(setting).to_s])

    if result.ok
      ticket.update!(artifacts: ticket.artifacts | ["change archived: #{change}"])
      accrue(result, ticket)
      Event.record!(phase_tag: "SPEC", tone: "var(--ok)", ticket: ticket, agent_name: "Shipper",
                    meta: "#{(result.duration_ms.to_i / 1000.0).round}s",
                    text: "Change #{change} archived into the permanent spec tree")
    else
      Event.record!(phase_tag: "SPEC", tone: "var(--err)", ticket: ticket, agent_name: "Shipper",
                    text: "Archiving #{change} failed: #{result.error.to_s.truncate(120)}")
    end
    PipelineEngine.broadcast
  end

  private

  def accrue(result, ticket)
    cost = result.cost.to_f.round(4)
    return unless cost.positive?

    SpendEntry.record!(cost, source: "archive", ticket: ticket, llm_model: HeadlessAgent.model_name)
  end
end
