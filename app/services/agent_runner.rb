# Chooses how a ticket's phases get executed:
#   demo — the simulated driver (tick thresholds + DemoScript narrative)
#   live — a real headless Claude Code process per phase (ClaudeCodeRunner)
#
# PIPELINE_RUNNER=auto (default) uses live execution per-ticket whenever the
# CLI, auth and the ticket's repo are all present; "demo" forces simulation;
# "live" refuses to fall back silently (tickets without a repo stay demo, but
# availability problems surface as events).
module AgentRunner
  module_function

  def mode
    ENV.fetch("PIPELINE_RUNNER", "auto")
  end

  def live_available?
    mode != "demo" && ClaudeCodeRunner.available?
  end

  # Can THIS ticket run live right now?
  def live?(ticket)
    live_available? && Workspace.repo_path(ticket.repo).present?
  end

  # Kick off real execution of the ticket's current phase. Returns true when
  # a live run was started, false when the demo driver should handle it.
  def start_phase(ticket)
    return false unless live?(ticket)

    RunPhaseJob.perform_later(ticket.id, ticket.state)
    true
  end
end
