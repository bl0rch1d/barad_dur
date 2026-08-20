require "test_helper"

# Every phase now returns a contract, and every contract is read back. A shape
# the skill emits that Ruby never parses is a phase reporting into the void.
class PhaseContractsTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(code: "TST-CT", title: "t", repo: "sample-repo", state: :implementation,
                             acceptance_criteria: ["Repeat runs hit the cache", "It invalidates"])
  end

  def runner(phase)
    run = @ticket.phase_runs.create!(phase: phase, status: "running", started_at: Time.current)
    [ClaudeCodeRunner.new(@ticket, run), run]
  end

  test "all six phases ask for a contract and stamp it with their own sentinel" do
    Ticket::PHASES.each do |phase|
      contract = PhasePrompts.contract_for(@ticket, phase)

      assert contract.present?, "#{phase} asks for nothing back"
      assert_includes contract, %("_c": "#{phase}.v1"),
                      "#{phase}'s block cannot be told apart from the other JSON in a long report"
    end
  end

  # ── implementation ───────────────────────────────────────────────────
  test "a deviation from the plan is recorded and surfaced, not left in prose" do
    r, run = runner("implementation")

    r.send(:apply_implementation_output,
           { "deviations" => [{ "from_plan" => "step 4", "why" => "the column already existed" }],
             "criteria_addressed" => [{ "id" => 1, "path" => "app/cache.rb:88" }] })

    assert_equal 1, run.reload.deviations.size
    assert_equal "app/cache.rb:88", run.criteria_results.first["path"]
    assert_match(/departed from the plan/i, Event.where(meta: "deviation").last.text)
  end

  test "an implementation that followed the plan raises nothing" do
    r, run = runner("implementation")

    r.send(:apply_implementation_output, { "deviations" => [], "criteria_addressed" => [] })

    assert_empty run.reload.deviations
    assert_nil Event.where(meta: "deviation").last
  end

  # ── testing ──────────────────────────────────────────────────────────
  test "an explicit executed:false is believed over a zero count" do
    r, run = runner("testing")

    r.send(:capture_test_results, { "executed" => false, "passed" => 0, "failed" => 0 })

    refute run.reload.tests_executed?, "0 passed / 0 failed is exactly what no suite looks like"
  end

  test "a criterion with no passing test makes the whole verification red" do
    r, run = runner("testing")

    r.send(:capture_test_results,
           { "executed" => true, "passed" => 128, "failed" => 0, "command" => "rspec",
             "criteria" => [{ "id" => 1, "verdict" => "satisfied", "test" => "spec/a_spec.rb:41" },
                            { "id" => 2, "verdict" => "not_satisfied", "test" => nil }] })

    assert_equal 2, run.reload.criteria_results.size
    assert_match(/1 criteria unmet/, run.note)
    assert_equal 1, @ticket.reload.criteria_unsatisfied.size
    assert @ticket.verification_red?, "128 passing tests say nothing about criterion 2"
    assert_equal "[criteria unmet] ", PushPrJob.new.send(:pr_prefix, @ticket)
  end

  test "an unrecognised verdict is read as not satisfied rather than as a pass" do
    r, run = runner("testing")

    r.send(:capture_test_results,
           { "executed" => true, "passed" => 1, "failed" => 0,
             "criteria" => [{ "id" => 1, "verdict" => "mostly fine" }] })

    assert_equal "not_satisfied", run.reload.criteria_results.first["verdict"]
  end

  test "untestable is honest, and does not make the ticket red" do
    r, run = runner("testing")

    r.send(:capture_test_results,
           { "executed" => true, "passed" => 9, "failed" => 0,
             "criteria" => [{ "id" => 1, "verdict" => "untestable", "test" => nil }] })

    assert_empty @ticket.reload.criteria_unsatisfied
  end

  # ── deployment ───────────────────────────────────────────────────────
  test "hygiene the shipper could not clear stops the ticket for a person" do
    r, run = runner("deployment")

    r.send(:apply_deploy_output, { "changelog" => true, "hygiene" => { "blocking" => [".env is staged"] } })

    assert_match(/1 blocking/, run.reload.note)
    assert_includes @ticket.reload.feedback, ".env is staged"
    assert_match(/not clean to commit/i, Event.where(meta: "hygiene").last.text)
  end

  test "no changelog in the repo is a success, not a skipped step" do
    r, run = runner("deployment")

    r.send(:apply_deploy_output, { "changelog" => false, "hygiene" => { "blocking" => [] } })

    assert_match(/no changelog in this repo/i, run.reload.note)
    assert_nil @ticket.reload.feedback
  end
end
