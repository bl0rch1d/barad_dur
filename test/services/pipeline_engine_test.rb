require "test_helper"

class PipelineEngineTest < ActiveSupport::TestCase
  setup do
    Setting.instance.update!(running: true, autonomy: "auto", spend_today: 0, spend_cap: 80, tick_count: 0)
  end

  def build_in_flight_ticket(state: :investigation, progress: 0, risky: false)
    agent = Agent.create!(name: "Builder-T", abbr: "BT", role: "implementation",
                          llm_model: "sonnet", status: "running")
    ticket = Ticket.create!(code: "TST-1", title: "Test ticket", repo: "algo-core",
                            state: state, agent: agent, phase_progress: progress, risky: risky)
    ticket.phase_runs.create!(phase: ticket.state, status: "running", started_at: 10.minutes.ago)
    ticket
  end

  test "tick emits activity and accrues spend" do
    build_in_flight_ticket
    # one activity event + one backlog-grooming event (board is otherwise empty)
    assert_difference -> { Event.count }, +2 do
      PipelineEngine.tick!
    end
    assert Setting.instance.spend_today.positive?
    assert_equal 1, Setting.instance.tick_count
  end

  test "tick advances a ticket past its phase threshold" do
    ticket = build_in_flight_ticket(progress: Ticket::PHASE_THRESHOLDS["investigation"] - 1)
    PipelineEngine.tick!
    assert_equal "planning", ticket.reload.state
    assert_equal 0, ticket.phase_progress
    assert_equal "done", ticket.phase_runs.find_by(phase: "investigation").status
    assert_equal "running", ticket.phase_runs.find_by(phase: "planning").status
  end

  test "every-autonomy gates the transition until approved" do
    Setting.instance.update!(autonomy: "every")
    ticket = build_in_flight_ticket(progress: Ticket::PHASE_THRESHOLDS["investigation"] - 1)

    PipelineEngine.tick!
    assert_equal "investigation", ticket.reload.state
    gate = ticket.ticket_gates.pending.first
    assert gate.present?
    assert_match ticket.code, gate.reason

    # gated ticket makes no further progress
    progress_before = ticket.phase_progress
    PipelineEngine.tick!
    assert_equal progress_before, ticket.reload.phase_progress

    PipelineEngine.approve_gate!(gate)
    assert_equal "planning", ticket.reload.state
    assert_equal "approved", gate.reload.status
  end

  test "risky-autonomy gates deployment for everyone" do
    Setting.instance.update!(autonomy: "risky")
    ticket = build_in_flight_ticket(state: :testing,
                                    progress: Ticket::PHASE_THRESHOLDS["testing"] - 1)
    PipelineEngine.tick!
    assert_equal "testing", ticket.reload.state
    assert ticket.ticket_gates.pending.exists?
  end

  test "finishing deployment completes the ticket and frees the agent" do
    ticket = build_in_flight_ticket(state: :deployment,
                                    progress: Ticket::PHASE_THRESHOLDS["deployment"] - 1)
    Release.create!(version: "v9.9.9", kind: "staged", position: 0, lines: [])
    PipelineEngine.tick!
    ticket.reload
    assert_equal "done", ticket.state
    assert ticket.finished_at.present?
    assert_includes Release.staged.lines, ticket.title
    # the freed agent may immediately pick up groomed work, but never this ticket
    refute_includes ticket.agent.tickets.in_flight, ticket
  end

  test "questions block progress until answered" do
    ticket = build_in_flight_ticket(progress: Ticket::PHASE_THRESHOLDS["investigation"] - 1)
    question = Question.create!(ticket_code: ticket.code, phase: "investigation",
                                body: "Which way?", options: ["A", "B"], asked_at: Time.current)
    PipelineEngine.tick!
    assert_equal "investigation", ticket.reload.state

    PipelineEngine.answer_question!(question, "A")
    assert_equal "answered", question.reload.status
    PipelineEngine.tick!
    assert_equal "planning", ticket.reload.state
  end

  test "spend cap pauses the pipeline once" do
    Setting.instance.update!(spend_today: 100)
    build_in_flight_ticket
    assert_difference -> { Event.count }, +1 do
      PipelineEngine.tick!
    end
    refute Setting.instance.running?
    assert_no_difference -> { Event.count } do
      PipelineEngine.tick!
    end
  end

  test "engine grooms backlog and fabricates new work when the board runs dry" do
    Agent.create!(name: "Idle-G", abbr: "IG", role: "implementation",
                  llm_model: "sonnet", status: "idle")
    backlog = Ticket.create!(code: "TST-5", title: "Backlog ticket", state: :draft)

    PipelineEngine.tick!
    assert_equal "investigation", backlog.reload.state

    Agent.update_all(status: "idle")
    assert_difference -> { Ticket.count }, +1 do
      PipelineEngine.tick!
    end
    fabricated = Ticket.order(:id).last
    assert_match(/\AALG-\d+\z/, fabricated.code)
  end

  test "idle agents pull ready tickets into investigation" do
    Agent.create!(name: "Idle-T", abbr: "IT", role: "implementation",
                  llm_model: "sonnet", status: "idle")
    ticket = Ticket.create!(code: "TST-2", title: "Ready ticket", state: :ready)
    PipelineEngine.tick!
    ticket.reload
    assert_equal "investigation", ticket.state
    assert ticket.agent.present?
    assert_equal "running", ticket.agent.status
  end

  test "planning parks at ready_to_implement and frees the agent" do
    ticket = build_in_flight_ticket(state: :planning,
                                    progress: Ticket::PHASE_THRESHOLDS["planning"] - 1)
    PipelineEngine.tick!
    ticket.reload
    assert_equal "ready_to_implement", ticket.state
    assert_equal "idle", ticket.agent.reload.status
    assert Event.exists?(["text LIKE ?", "%groomed — ready to implement%"])
  end

  test "ready_to_implement tickets are picked up for implementation, dep-gated" do
    Agent.create!(name: "Impl-T", abbr: "IP", role: "implementation",
                  llm_model: "sonnet", status: "idle")
    dep = Ticket.create!(code: "TST-D1", title: "Prerequisite", state: :implementation)
    blocked = Ticket.create!(code: "TST-A1", title: "Waits on dep", state: :ready_to_implement,
                             dep_codes: ["TST-D1"])
    free = Ticket.create!(code: "TST-B1", title: "No deps", state: :ready_to_implement)

    PipelineEngine.tick!
    assert_equal "ready_to_implement", blocked.reload.state, "dep-blocked ticket must wait"
    assert_equal "implementation", free.reload.state
    assert_equal "dependency", blocked.blocker[:type]
    assert_match(/TST-D1/, blocked.blocker[:label])

    dep.update!(state: :done)
    Agent.create!(name: "Impl-T2", abbr: "I2", role: "implementation",
                  llm_model: "sonnet", status: "idle")
    PipelineEngine.tick!
    assert_equal "implementation", blocked.reload.state, "unblocks once dep is done"
  end

  test "gate-all autonomy gates the ready_to_implement pickup" do
    Setting.instance.update!(autonomy: "every")
    Agent.create!(name: "Gate-T", abbr: "GT", role: "implementation",
                  llm_model: "sonnet", status: "idle")
    ticket = Ticket.create!(code: "TST-G1", title: "Gated pickup", state: :ready_to_implement)

    PipelineEngine.tick!
    assert_equal "ready_to_implement", ticket.reload.state
    gate = ticket.ticket_gates.pending.first
    assert gate.present?
    assert_equal "gate", ticket.blocker[:type]

    PipelineEngine.approve_gate!(gate)
    assert_equal "implementation", ticket.reload.state
  end
end
