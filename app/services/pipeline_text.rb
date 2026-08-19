# Shared vocabulary for pipeline narration: event tags, phase placeholders
# and the human-readable lines the engine writes to the feed.
module PipelineText
  TAGS = {
    "investigation"  => "INVEST",
    "planning"       => "PLAN",
    "implementation" => "IMPL",
    "review"         => "REVIEW",
    "testing"        => "TEST",
    "deployment"     => "DEPLOY"
  }.freeze

  PHASE_NOTES = {
    "investigation"  => "reading code, call sites and history",
    "planning"       => "writing the change: proposal, design, tasks",
    "implementation" => "patching on a pipe/* branch",
    "review"         => "reviewing the diff against the spec",
    "testing"        => "running the repo's test suite",
    "deployment"     => "changelog and release preparation"
  }.freeze

  TRANSITION_TEXT = {
    "planning"       => "Investigation complete — entering planning",
    "implementation" => "Plan accepted — implementation started",
    "review"         => "Implementation done — handed to review",
    "testing"        => "Review passed — running the test suite",
    "deployment"     => "Tests green — preparing the release"
  }.freeze

  module_function

  def note_for(phase)
    PHASE_NOTES[phase]
  end

  def transition_text(ticket, _from, to)
    "#{TRANSITION_TEXT.fetch(to, "Entering #{to}")} (#{ticket.code})"
  end

  def start_text(ticket)
    "Picked up #{ticket.code} — #{ticket.title}"
  end

  def doing_text(ticket)
    "#{ticket.code} #{ticket.state}: #{ticket.title.downcase.truncate(48)}"
  end

  # Shown on the gate a ticket parks on once the agents are finished with it.
  def verdict_reason(ticket)
    case Features.landing
    when "pull_request"
      ticket.pr_url.present? ? "#{ticket.code} is ready — approve to merge its pull request" :
                               "#{ticket.code} is ready — approve once its pull request is open"
    when "local_merge" then "#{ticket.code} is ready — approve to merge it into the default branch"
    else "#{ticket.code} is ready — approve to mark it shipped; the branch is yours to land"
    end
  end

  def gate_reason(ticket, next_state, mode)
    if mode == "every"
      "#{ticket.code} finished #{ticket.state} — approve to enter #{next_state}."
    elsif ticket.risky?
      "#{ticket.code} is marked risky — approve to enter #{next_state}."
    else
      "#{ticket.code} is ready to deploy — approve the rollout."
    end
  end
end
