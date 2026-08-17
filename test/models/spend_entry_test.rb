require "test_helper"

class SpendEntryTest < ActiveSupport::TestCase
  setup { Setting.instance.update!(spend_cap: 80) }

  test "sub-cent charges are kept, not rounded away" do
    20.times { SpendEntry.record!(0.004, source: "phase") }
    assert_equal 0.08, SpendEntry.total_today.to_f, "20 x $0.004 must total $0.08"
  end

  test "repeated charges do not drift" do
    20.times { SpendEntry.record!(0.026, source: "phase") }
    # the old per-accrual rounding turned this into $0.60
    assert_equal 0.52, SpendEntry.total_today.to_f
  end

  test "today means today — yesterday's spend does not count against the cap" do
    SpendEntry.record!(70, source: "phase", at: 2.days.ago)
    SpendEntry.record!(20, source: "phase", at: 1.day.ago)
    SpendEntry.record!(5, source: "phase")

    assert_equal 5, Setting.instance.spend_today.to_f, "only today's charges"
    refute Setting.instance.over_cap?, "yesterday's $90 must not quench today"
    assert_equal 95, SpendEntry.sum(:amount).to_f, "history is still all there"
  end

  test "charges are attributed to their ticket, agent, phase and model" do
    agent = Agent.create!(name: "Builder", abbr: "BD", role: "implementation", llm_model: "x")
    ticket = Ticket.create!(code: "TST-C1", title: "Costed", state: :implementation)

    SpendEntry.record!(0.25, source: "phase", phase: "implementation",
                       ticket: ticket, agent: agent, llm_model: "claude-opus-5")

    entry = SpendEntry.last
    assert_equal "TST-C1", entry.ticket_code
    assert_equal "implementation", entry.phase
    assert_equal "claude-opus-5", entry.llm_model
    assert_equal 0.25, agent.cost_today.to_f
    assert_equal 0.25, ticket.reload.cost.to_f, "the ticket cache follows the ledger"
  end

  test "zero and negative charges are ignored" do
    assert_nil SpendEntry.record!(0, source: "phase")
    assert_nil SpendEntry.record!(-1, source: "phase")
    assert_equal 0, SpendEntry.count
  end

  test "hourly bars are contiguous, including hours with no spend" do
    now = Time.current.beginning_of_hour
    SpendEntry.record!(1.5, source: "phase", at: now)
    SpendEntry.record!(2.0, source: "phase", at: now - 3.hours)

    bars = SpendEntry.hourly_bars(4, now: now)
    assert_equal 4, bars.size
    assert_equal [2.0, 0.0, 0.0, 1.5], bars.map { |b| b.amount.to_f },
                 "idle hours appear as empty bars rather than being skipped"
    assert_equal now, bars.last.bucket
  end

  test "totals cannot drift apart because they share one source" do
    agent = Agent.create!(name: "Scout", abbr: "SC", role: "investigation", llm_model: "x")
    ticket = Ticket.create!(code: "TST-C2", title: "Sum", state: :investigation)
    SpendEntry.record!(0.11, source: "phase", ticket: ticket, agent: agent)
    SpendEntry.record!(0.07, source: "chat", agent: agent)

    assert_equal Setting.instance.spend_today.to_f, agent.cost_today.to_f
    assert_equal 0.18, Setting.instance.spend_today.to_f
  end
end
