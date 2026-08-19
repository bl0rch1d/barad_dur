require "test_helper"

# The sweeper kills runs whose process died. It has to use the limit the runner
# actually gave that phase — a single global cutoff has now been wrong in both
# directions, and each time it marked a working agent dead.
class BudgetSweepTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(code: "TST-SW", title: "t", repo: "sample-repo", state: :review)
  end

  def run_at(phase, age)
    run = @ticket.phase_runs.create!(phase: phase, status: "running", runner: "claude",
                                     started_at: age.ago)
    run.update_column(:updated_at, age.ago)
    run
  end

  test "a review still working past the global default is not swept" do
    run = run_at("review", 50.minutes)

    PipelineEngine.sweep_stale_runs!

    assert_equal "running", run.reload.status,
                 "review is allowed 5400s; the old cutoff killed it at 2820s"
  end

  test "a review past its own budget is swept" do
    run = run_at("review", 100.minutes)

    assert_equal 1, PipelineEngine.sweep_stale_runs!
    assert_equal "failed", run.reload.status
  end

  test "a short phase is swept on its own budget, not on review's" do
    run = run_at("deployment", 30.minutes)

    assert_equal 1, PipelineEngine.sweep_stale_runs!
    assert_equal "failed", run.reload.status,
                 "deployment is allowed 900s — waiting for review's 5400s freezes the ticket"
  end

  test "a fresh run is left alone whatever its phase" do
    %w[investigation implementation review].each { |phase| run_at(phase, 2.minutes) }

    assert_equal 0, PipelineEngine.sweep_stale_runs!
  end

  test "the candidate query is the shortest budget, so no phase escapes it" do
    window = PipelineEngine.send(:shortest_budget)

    PhasePrompts::BUDGETS.each do |phase, budget|
      assert_operator window, :<=, budget[:timeout],
                      "#{phase} would never become a candidate and would freeze its ticket"
    end
  end
end
