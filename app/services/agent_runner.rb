# Gate for real agent execution. PIPELINE_RUNNER=off is the kill-switch
# (used by the test harness); otherwise a ticket is executable when the CLI,
# auth and its repo are all present. Tickets that aren't executable simply
# wait in place — the engine never simulates work.
module AgentRunner
  module_function

  def mode
    ENV.fetch("PIPELINE_RUNNER", "auto")
  end

  def live_available?
    !%w[demo off].include?(mode) && ClaudeCodeRunner.available?
  end

  # Can THIS ticket run live right now?
  def live?(ticket)
    live_available? && Workspace.repo_path(ticket.repo).present?
  end

  # Kick off real execution of the ticket's current phase. Returns false
  # when the runner isn't available for this ticket.
  def start_phase(ticket)
    return false unless live?(ticket)

    RunPhaseJob.perform_later(ticket.id, ticket.state)
    true
  end
end
