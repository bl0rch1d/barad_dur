require "test_helper"

# Testing is the last automated gate before a pull request is opened for a
# human, so it has to cover more than "the unit tests passed".
class TestingPhaseTest < ActiveSupport::TestCase
  test "the prompt asks for linters, unit, regression and e2e in that order" do
    ticket = Ticket.create!(code: "TST-T1", title: "Covered", state: :testing)
    prompt = PhasePrompts.build(ticket, "testing")

    %w[Linters unit regression End-to-end].each do |wanted|
      assert_match(/#{wanted}/i, prompt, "the tester should be told about #{wanted}")
    end
    assert_operator prompt.index(/linter/i), :<, prompt.index(/unit test/i), "linters run first"
    assert_operator prompt.index(/regression/i), :<, prompt.index(/end-to-end/i)
    assert_match(/pull request is opened for human review/i, prompt,
                 "it should know why this is the last gate")
    assert_match(/never weaken, skip or delete a test/i, prompt)
  end

  test "the contract asks for a per-suite breakdown including what could not run" do
    ticket = Ticket.create!(code: "TST-TC", title: "Contract", state: :testing)
    contract = PhasePrompts.contract_for(ticket, "testing")
    assert_match(/suites/, contract)
    assert_match(/skipped/, contract)
    assert_match(/"kind"/, contract)
  end

  test "a red suite opens the pull request as a draft" do
    ticket = Ticket.create!(code: "TST-T2", title: "Red", state: :testing)
    ticket.phase_runs.create!(phase: "testing", status: "done", runner: "claude",
                              tests_passed: 40, tests_failed: 3, started_at: Time.current)
    assert ticket.tests_failed?, "the latest testing run decides"

    green = Ticket.create!(code: "TST-T3", title: "Green", state: :testing)
    green.phase_runs.create!(phase: "testing", status: "done", runner: "claude",
                             tests_passed: 40, tests_failed: 0, started_at: Time.current)
    refute green.tests_failed?
  end

  test "the latest run wins when a ticket was tested more than once" do
    ticket = Ticket.create!(code: "TST-T4", title: "Fixed", state: :testing)
    ticket.phase_runs.create!(phase: "testing", status: "done", runner: "claude",
                              tests_passed: 10, tests_failed: 5, started_at: 1.hour.ago)
    ticket.phase_runs.create!(phase: "testing", status: "done", runner: "claude",
                              tests_passed: 15, tests_failed: 0, started_at: Time.current)

    refute ticket.reload.tests_failed?, "the rerun that went green is the one that counts"
  end
end
