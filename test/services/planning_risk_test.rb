require "test_helper"

# The "risky" autonomy mode asks a person before an agent writes code on a
# dangerous ticket. It reads Ticket#risky, which only a human checkbox ever
# set — so the mode did nothing for the tickets that most needed it.
class PlanningRiskTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(code: "TST-K1", title: "Drop the legacy orders table",
                             repo: "sample-repo", state: :planning)
    @run = @ticket.phase_runs.create!(phase: "planning", status: "running", started_at: Time.current)
    @runner = ClaudeCodeRunner.new(@ticket, @run)
  end

  def plan(data) = @runner.send(:apply_plan_output, data)

  test "planning can mark a ticket risky, and says why" do
    plan({ "risky" => true, "risk_reason" => "drops a table with production data" })

    assert @ticket.reload.risky?
    assert_match(/drops a table/, Event.where(meta: "risky").last.text)
  end

  test "a plan that says nothing about risk leaves the ticket alone" do
    plan({ "summary" => "a small change" })

    refute @ticket.reload.risky?
  end

  test "planning never clears a risk the user set by hand" do
    @ticket.update!(risky: true)

    plan({ "risky" => false })

    assert @ticket.reload.risky?, "the user's own judgement outranks the agent's"
  end

  test "the risky gate now actually fires on a ticket planning flagged" do
    Setting.instance.update!(autonomy: "risky")
    plan({ "risky" => true })

    assert PipelineEngine.send(:gate_required?, Setting.instance, @ticket.reload, "implementation"),
           "this is the whole point of the risky autonomy mode"
  end

  test "the planning contract explains what counts as risky rather than leaving it to taste" do
    contract = PhasePrompts::PLANNING_CONTRACT

    assert_match(/"risky"/, contract)
    assert_match(/schema/i, contract)
    assert_match(/marking everything risky asks the user for nothing/i, contract,
                 "an agent told only 'be careful' marks everything risky")
  end
end
