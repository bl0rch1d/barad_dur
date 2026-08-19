require "test_helper"

# Deployment is off by default, so work stops after the last enabled phase and
# waits for a verdict instead of marking itself shipped.
class LandingTest < ActiveSupport::TestCase
  setup do
    Setting.instance.update!(running: true, autonomy: "auto", spend_cap: 80, setup_complete: true)
    ENV["PIPELINE_RUNNER"] = "off"
  end

  def finished(code, state:, deps: [])
    ticket = Ticket.create!(code: code, title: code, repo: "sample-repo", state: state, dep_codes: deps)
    ticket.phase_runs.create!(phase: state, status: "running", runner: "claude", started_at: Time.current)
    ticket
  end

  test "deployment is off by default and the column is a dead end" do
    refute Features.deployment?
    assert_equal "testing", Features.last_enabled_phase
    assert_equal %w[investigation planning implementation review testing], Features.enabled_phases
  end

  test "finishing the last enabled phase parks for a verdict instead of shipping" do
    ticket = finished("TST-L1", state: :testing)

    PipelineEngine.phase_finished!(ticket)

    ticket.reload
    assert_equal "testing", ticket.state, "it does not advance into a disabled phase"
    refute ticket.done?, "nothing is shipped without a verdict"
    assert ticket.gated?, "it waits on a gate"
    assert_equal Ticket::STATES[:done], ticket.ticket_gates.pending.first.to_state
    assert_match(/ready/, ticket.ticket_gates.pending.first.reason)
  end

  test "a ticket awaiting your verdict holds back everything that depends on it" do
    parent = finished("TST-L2", state: :testing)
    child = Ticket.create!(code: "TST-L3", title: "dependent", repo: "sample-repo",
                           state: :ready_to_implement, dep_codes: ["TST-L2"])

    PipelineEngine.phase_finished!(parent)

    refute child.reload.deps_satisfied?, "the parent is not done, so the child waits"
    assert_equal({ type: "dependency", label: "waiting on TST-L2" }, child.blocker)

    # approving lands the parent, which releases the child
    PipelineEngine.approve_gate!(parent.reload.ticket_gates.pending.first)

    assert parent.reload.done?
    assert child.reload.deps_satisfied?, "the child is released once you approve"
  end

  test "enabling deployment restores the old straight-through behaviour" do
    Setting.instance.update!(setup: Setting.instance.setup.merge("phase:deployment" => "1"))
    ticket = finished("TST-L4", state: :testing)

    PipelineEngine.phase_finished!(ticket)

    assert_equal "deployment", ticket.reload.state
    refute ticket.gated?
  end

  test "a disabled middle phase is skipped rather than parked on" do
    Setting.instance.update!(setup: Setting.instance.setup.merge("phase:review" => "0"))
    ticket = finished("TST-L5", state: :implementation)

    PipelineEngine.phase_finished!(ticket)

    assert_equal "testing", ticket.reload.state, "review is skipped, testing still runs"
  end

  test "landing mode decides what approving does" do
    assert_equal "pull_request", Features.landing, "opening a PR is the default"

    # approving with no PR open still closes the ticket, and says so plainly
    ticket = Ticket.create!(code: "TST-L6", title: "no pr", repo: "sample-repo", state: :testing)
    result = LandWork.merge_pull_request(ticket)
    assert result.ok, "a missing PR must not strand the ticket"
    assert_match(/unmerged/, result.message)

    Setting.instance.update!(setup: Setting.instance.setup.merge("landing" => "manual"))
    LandWork.call(ticket)
    assert ticket.reload.done?, "manual landing just marks it shipped"
  end
end
