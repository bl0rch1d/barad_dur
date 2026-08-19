require "test_helper"

# Review reports; implementation fixes. That split only holds if a blocking
# finding actually moves the ticket — otherwise review is a phase that writes
# prose and changes nothing.
class ReviewVerdictTest < ActiveSupport::TestCase
  setup do
    @agent = Agent.create!(name: "Critic", abbr: "CR", role: "review", status: "running",
                          llm_model: "claude-opus-4-6")
    @ticket = Ticket.create!(code: "TST-R1", title: "Cache metadata", repo: "sample-repo",
                             state: :review, agent: @agent,
                             acceptance_criteria: ["repeat runs hit the cache"])
    @run = @ticket.phase_runs.create!(phase: "review", status: "running", started_at: Time.current)
    @runner = ClaudeCodeRunner.new(@ticket, @run)
  end

  def apply(data, reroute: true)
    @runner.send(:apply_review_output, data, reroute: reroute)
  end

  test "a blocking finding sends the ticket back to implementation with the finding as feedback" do
    result = apply({
      "verdict" => "changes_requested",
      "findings" => [{ "severity" => "blocking", "file" => "app/cache.rb:12",
                       "what" => "the cache key omits the venue",
                       "why" => "two venues return each other's prices" }]
    })

    assert_equal :rerouted, result, "the runner must not also advance the ticket"
    @ticket.reload
    assert_equal "implementation", @ticket.state
    assert_includes @ticket.feedback, "the cache key omits the venue"
    assert_includes @ticket.feedback, "app/cache.rb:12", "the builder needs to know where"
  end

  test "only minor findings pass, and the ticket carries on" do
    result = apply({ "verdict" => "pass",
                     "findings" => [{ "severity" => "minor", "what" => "the name reads oddly" }] })

    assert_nil result
    assert_equal "review", @ticket.reload.state
    assert_equal "pass", @run.reload.review_verdict
    assert_equal 1, @run.review_findings.size
  end

  test "a verdict claiming pass while reporting a blocker is read as changes requested" do
    apply({ "verdict" => "pass",
            "findings" => [{ "severity" => "blocking", "what" => "drops the last row" }] })

    assert_equal "changes_requested", @run.reload.review_verdict,
                 "the findings decide the verdict, not the label the agent typed"
  end

  test "rework stops after its budget and the findings travel to the operator instead" do
    3.times { @ticket.phase_runs.create!(phase: "implementation", status: "done", started_at: Time.current) }

    result = apply({ "findings" => [{ "severity" => "blocking", "what" => "still wrong" }] })

    assert_nil result, "past the budget it stops arguing with itself"
    assert_equal "review", @ticket.reload.state
    assert_includes @ticket.feedback, "still wrong", "the operator still has to see why"
    assert Event.where(meta: "unresolved").exists?
  end

  test "a findings-free review is recorded as clean rather than as nothing" do
    apply({ "verdict" => "pass", "findings" => [] })

    assert_equal "pass", @run.reload.review_verdict
    assert_match(/clean/i, @run.note)
  end

  test "a failed run never reroutes, however blocking its findings" do
    result = apply({ "findings" => [{ "severity" => "blocking", "what" => "wrong" }] }, reroute: false)

    assert_nil result
    assert_equal "review", @ticket.reload.state, "two live runs is worse than a lost round"
    assert_equal 1, @run.reload.review_findings.size, "but the findings are still kept"
  end

  test "malformed findings are dropped rather than crashing the phase" do
    apply({ "findings" => ["a string", { "severity" => "blocking" }, { "what" => "  " },
                           { "severity" => "blocking", "what" => "real one" }] })

    findings = @run.reload.review_findings
    assert_equal 1, findings.size
    assert_equal "real one", findings.first["what"]
  end

  test "the built-in review prompt tells the critic not to fix what it finds" do
    prompt = PhasePrompts.build(@ticket, "review") + PhasePrompts.contract_for(@ticket, "review")

    assert_match(/do NOT edit, commit, or fix/i, prompt)
    assert_match(/"verdict"/, prompt, "and it has to report the verdict in a form we can read")
  end
end
