require "test_helper"

# Turns and wall-clock each have a limit, and a phase can sit inside both while
# burning a fortune. The daily cap was read only before a ticket was picked up,
# so runs already in flight could pass it together with nothing to stop them.
class SpendGuardTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(code: "TST-SG", title: "t", repo: "sample-repo", state: :review)
    @run = @ticket.phase_runs.create!(phase: "review", status: "running", started_at: Time.current)
    @runner = ClaudeCodeRunner.new(@ticket, @run)
  end

  def usage(input: 0, output: 0, cache_read: 0)
    { "type" => "assistant",
      "message" => { "usage" => { "input_tokens" => input, "output_tokens" => output,
                                  "cache_read_input_tokens" => cache_read } } }
  end

  test "a run inside its ceiling is left alone" do
    guard = @runner.send(:spend_guard, 10_000)

    5.times { assert_nil guard.call(usage(input: 1_000, output: 100)) }
  end

  test "a run that will not converge is stopped, and told why" do
    guard = @runner.send(:spend_guard, 10_000)

    reason = nil
    20.times { reason ||= guard.call(usage(input: 1_000, output: 100)) }

    assert reason, "nothing stopped a run past its ceiling"
    assert_match(/tokens/, reason)
    assert_match(/split the ticket|CLAUDE_MAX_TOKENS/, reason, "and says what to do about it")
  end

  test "cached reads count — they are billed, and a loop re-reads the same context" do
    guard = @runner.send(:spend_guard, 5_000)

    reason = nil
    10.times { reason ||= guard.call(usage(cache_read: 1_000)) }

    assert reason
  end

  test "a message carrying no usage is not treated as zero-cost progress" do
    guard = @runner.send(:spend_guard, 100)

    assert_nil guard.call({ "type" => "system", "session_id" => "abc" })
    assert_nil guard.call({ "type" => "assistant", "message" => {} })
  end

  test "a message shaped differently does not take down the run it guards" do
    guard = @runner.send(:spend_guard, 100)

    # "message" is a Hash on assistant turns and a plain string elsewhere;
    # dig on a String raises, and this lambda runs on every streamed message.
    assert_nothing_raised do
      assert_nil guard.call({ "type" => "result", "message" => "all done" })
      assert_nil guard.call({ "type" => "result", "message" => nil })
      assert_nil guard.call({ "type" => "assistant", "message" => { "usage" => "unexpected" } })
      assert_nil guard.call({})
    end
  end

  test "no ceiling configured means the token check never fires" do
    guard = @runner.send(:spend_guard, nil)

    100.times { assert_nil guard.call(usage(input: 100_000)) }
  end

  test "every phase carries a ceiling, so none runs unguarded" do
    Ticket::PHASES.each do |phase|
      budget = PhasePrompts.budget_for(phase)
      assert budget[:max_tokens].to_i.positive?, "#{phase} has no token ceiling"
      assert budget[:timeout].to_f.positive?, "#{phase} has no time limit"
      assert budget[:max_turns].to_i.positive?, "#{phase} has no turn limit"
    end
  end

  test "a run keeps going when the realm is still inside its cap" do
    Setting.instance.update!(spend_cap: 100)
    SpendEntry.record!(1.0, source: "phase", phase: "review", ticket: @ticket,
                       llm_model: "claude-opus-4-6")

    guard = @runner.send(:spend_guard, nil, 0)

    assert_nil guard.call(usage(input: 10))
  end

  test "a run is stopped when other runs push the realm past the cap beneath it" do
    Setting.instance.update!(spend_cap: 1)
    SpendEntry.record!(50.0, source: "phase", phase: "review", ticket: @ticket,
                       llm_model: "claude-opus-4-6")

    guard = @runner.send(:spend_guard, nil, 0)

    assert_match(/daily spend cap/, guard.call(usage(input: 10)).to_s)
  end

  test "the ledger is consulted on a timer, not once per streamed token" do
    Setting.instance.update!(spend_cap: 1)
    SpendEntry.record!(50.0, source: "phase", phase: "review", ticket: @ticket,
                       llm_model: "claude-opus-4-6")

    guard = @runner.send(:spend_guard, nil)

    assert_nil guard.call(usage(input: 10)),
               "a query per streamed message would cost more than the run it guards"
  end
end
