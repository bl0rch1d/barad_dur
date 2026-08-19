require "test_helper"

# Pausing the tower, and hitting the daily spend cap, both stopped it picking
# up *new* work — and let every ticket already in flight run all its remaining
# phases. That is the opposite of what either control is for.
class PauseHoldsWorkTest < ActiveSupport::TestCase
  setup do
    @setting = Setting.instance
    @setting.update!(setup_complete: true, autonomy: "auto")
    @agent = Agent.create!(name: "Builder", abbr: "BD", role: "implementation",
                           status: "running", llm_model: "claude-opus-4-6")
    @ticket = Ticket.create!(code: "TST-P1", title: "Mid-flight", repo: "sample-repo",
                             state: :implementation, agent: @agent)
    @ticket.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)
  end

  test "a stopped tower holds an in-flight ticket at its next phase instead of running it" do
    @setting.update!(running: false)

    PipelineEngine.send(:apply_transition, @ticket)

    @ticket.reload
    assert_equal "review", @ticket.state, "the ticket still advances — it just does not start"
    run = @ticket.current_phase_run
    assert_equal "paused", run.status
    assert_match(/tower is stopped/, run.note)
    assert_equal "idle", @agent.reload.status, "an agent with nothing running is not running"
  end

  test "the daily cap says so by name, since it is a different problem to fix" do
    @setting.update!(running: false, spend_cap: 5)
    SpendEntry.record!(9.0, source: "phase", phase: "implementation", ticket: @ticket,
                       llm_model: "claude-opus-4-6")

    PipelineEngine.send(:apply_transition, @ticket)

    assert_match(/spend cap/, @ticket.reload.current_phase_run.note)
  end

  test "the tower running again picks the held work back up" do
    @setting.update!(running: false)
    PipelineEngine.send(:apply_transition, @ticket)
    @setting.update!(running: true)

    assert_equal 1, PipelineEngine.send(:resume_paused_runs!)

    run = @ticket.reload.current_phase_run
    assert_equal "running", run.status
    assert_equal "review", run.phase
  end

  test "a held run whose ticket moved on is retired rather than run at the wrong phase" do
    @setting.update!(running: false)
    PipelineEngine.send(:apply_transition, @ticket)
    # a rework round sent it back while it was held
    @ticket.update!(state: :implementation)
    @setting.update!(running: true)

    assert_equal 0, PipelineEngine.send(:resume_paused_runs!)
    assert_equal "failed", PhaseRun.where(phase: "review").first.status
    assert_empty PhaseRun.paused, "a superseded hold must not linger and fire later"
  end

  test "a running tower starts the next phase as it always did" do
    @setting.update!(running: true)

    PipelineEngine.send(:apply_transition, @ticket)

    assert_equal "running", @ticket.reload.current_phase_run.status
    assert_empty PhaseRun.paused
  end
end
