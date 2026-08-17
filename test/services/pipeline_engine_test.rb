require "test_helper"

# Engine mechanics that don't need the CLI: transitions, parking, gates,
# dependencies, questions and the spend cap. Runner-dependent behavior lives
# in live_runner_test with the stub CLI.
class PipelineEngineTest < ActiveSupport::TestCase
  setup do
    Setting.instance.update!(running: true, autonomy: "auto",
                             spend_cap: 80, setup_complete: true)
  end

  def finished_run_ticket(state:, risky: false, code: "TST-1")
    agent = Agent.create!(name: "Agent-#{code}", abbr: "A#{code.last}", role: state.to_s,
                          llm_model: "opus 5", status: "running")
    ticket = Ticket.create!(code: code, title: "Test ticket", repo: "some-repo",
                            state: state, agent: agent, risky: risky)
    ticket.phase_runs.create!(phase: ticket.state, status: "done", runner: "claude",
                              started_at: 10.minutes.ago, finished_at: Time.current)
    ticket
  end

  test "phase_finished advances a ticket to the next phase" do
    ticket = finished_run_ticket(state: :investigation)
    PipelineEngine.phase_finished!(ticket)
    ticket.reload
    assert_equal "planning", ticket.state
    assert_equal "running", ticket.current_phase_run.status
    assert_equal "claude", ticket.current_phase_run.runner
  end

  test "planning parks at ready_to_implement and frees the agent" do
    ticket = finished_run_ticket(state: :planning)
    PipelineEngine.phase_finished!(ticket)
    ticket.reload
    assert_equal "ready_to_implement", ticket.state
    assert_equal "idle", ticket.agent.reload.status
    assert Event.exists?(["text LIKE ?", "%groomed — ready to implement%"])
  end

  test "deployment completion finishes the ticket" do
    ticket = finished_run_ticket(state: :deployment)
    Release.create!(version: "v9.9.9", kind: "staged", position: 0, lines: [])
    PipelineEngine.phase_finished!(ticket)
    ticket.reload
    assert_equal "done", ticket.state
    assert ticket.finished_at.present?
    assert_equal "idle", ticket.agent.reload.status
    assert_includes Release.staged.lines, ticket.title
  end

  test "every-autonomy gates transitions until approved" do
    Setting.instance.update!(autonomy: "every")
    ticket = finished_run_ticket(state: :investigation)

    PipelineEngine.phase_finished!(ticket)
    assert_equal "investigation", ticket.reload.state
    gate = ticket.ticket_gates.pending.first
    assert gate.present?
    assert_match ticket.code, gate.reason

    PipelineEngine.approve_gate!(gate)
    assert_equal "planning", ticket.reload.state
    assert_equal "approved", gate.reload.status
  end

  test "risky-autonomy gates risky implementation and deployment" do
    Setting.instance.update!(autonomy: "risky")
    ticket = finished_run_ticket(state: :testing, risky: true)
    PipelineEngine.phase_finished!(ticket)
    assert_equal "testing", ticket.reload.state
    assert ticket.ticket_gates.pending.exists?
  end

  test "pending questions park the ticket; answers resume it" do
    ticket = finished_run_ticket(state: :investigation)
    question = Question.create!(ticket_code: ticket.code, phase: "investigation",
                                body: "Which way?", options: %w[A B], asked_at: Time.current)

    PipelineEngine.phase_finished!(ticket)
    assert_equal "investigation", ticket.reload.state, "parked on clarification"
    assert_equal "clarification", ticket.blocker[:type]

    PipelineEngine.answer_question!(question, "A")
    assert_equal "answered", question.reload.status
    assert_equal "planning", ticket.reload.state, "resumes after the answer"
  end

  test "dependency-blocked tickets wait and unblock when deps complete" do
    dep = Ticket.create!(code: "TST-D1", title: "Prerequisite", state: :implementation)
    blocked = Ticket.create!(code: "TST-A1", title: "Waits", state: :ready_to_implement,
                             dep_codes: ["TST-D1"])
    assert_equal "dependency", blocked.blocker[:type]
    assert_match(/TST-D1/, blocked.blocker[:label])

    dep.update!(state: :done)
    assert_nil blocked.reload.blocker
  end

  test "spend cap quenches the pipeline" do
    SpendEntry.record!(100, source: "phase")
    assert_difference -> { Event.count }, +1 do
      PipelineEngine.tick!
    end
    refute Setting.instance.running?
    assert Event.exists?(["text LIKE ?", "%quenched%"])
    assert_no_difference -> { Event.count } do
      PipelineEngine.tick!
    end
  end

  test "manual ship completes a ticket from any phase" do
    ticket = finished_run_ticket(state: :review)
    PipelineEngine.manual_ship!(ticket, "merged pipe/tst-1 into master")
    ticket.reload
    assert_equal "done", ticket.state
    assert Event.exists?(["text LIKE ?", "%approved & merged%"])
  end
end
