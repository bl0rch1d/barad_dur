# What this realm has switched on. Stored in Setting#setup, so it belongs to
# the bound realm rather than the image or the environment — rebind elsewhere
# and that realm carries its own answers.
#
# Defaults live here and nowhere else: the rest of the app asks
# Features.deployment? rather than poking at setup keys.
module Features
  # Phases the pipeline may run. Deployment is off by default — it only
  # appends a changelog entry, and leaving it on means a ticket reaches "done"
  # without anyone having looked at it.
  PHASE_DEFAULTS = {
    "investigation" => true, "planning" => true, "implementation" => true,
    "review" => true, "testing" => true, "deployment" => false
  }.freeze

  # How finished work lands. Opening a pull request is the default: the tower
  # prepares the change, a human merges it.
  LANDING_MODES = {
    "pull_request" => "Open a pull request — approving merges it on GitHub",
    "local_merge" => "Merge into the default branch locally, never pushing",
    "manual" => "Neither — the pipe/* branch is left for you to handle"
  }.freeze
  DEFAULT_LANDING = "pull_request".freeze

  module_function

  def setting = Setting.instance

  def phase?(phase, s = setting)
    key = "phase:#{phase}"
    return PHASE_DEFAULTS.fetch(phase.to_s, true) unless s.setup.key?(key)

    s.setup[key] == "1"
  end

  def deployment?(s = setting) = phase?("deployment", s)

  # Phases that will actually run, in pipeline order.
  def enabled_phases(s = setting)
    Ticket::PHASES.select { |phase| phase?(phase, s) }
  end

  # The phase a ticket stops after — nothing enabled follows it.
  def last_enabled_phase(s = setting) = enabled_phases(s).last

  def landing(s = setting)
    mode = s.setup["landing"].to_s
    LANDING_MODES.key?(mode) ? mode : DEFAULT_LANDING
  end

  def pull_request?(s = setting) = landing(s) == "pull_request"
  def local_merge?(s = setting) = landing(s) == "local_merge"

  # Opening the PR is part of the pull-request flow, but a realm can keep the
  # flow and still open PRs by hand.
  def auto_pr?(s = setting)
    return pull_request?(s) unless s.setup.key?("auto_pr")

    s.setup["auto_pr"] == "1"
  end
end
