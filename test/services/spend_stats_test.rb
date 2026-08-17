require "test_helper"

class SpendStatsTest < ActiveSupport::TestCase
  setup { Setting.instance.update!(spend_cap: 80) }

  def shipped(code, cost:, implementation_runs: 1, at: 2.hours.ago)
    ticket = Ticket.create!(code: code, title: code, state: :done, finished_at: at)
    implementation_runs.times do
      ticket.phase_runs.create!(phase: "implementation", status: "done", runner: "claude",
                                started_at: at, duration_s: 60)
    end
    SpendEntry.record!(cost, source: "phase", phase: "implementation", ticket: ticket, at: at)
    ticket
  end

  test "cost per shipped ticket averages only finished work" do
    shipped("TST-A", cost: 1.00)
    shipped("TST-B", cost: 2.00)
    # in-flight work must not dilute the average
    wip = Ticket.create!(code: "TST-C", title: "wip", state: :implementation)
    SpendEntry.record!(5.00, source: "phase", ticket: wip)

    stats = SpendStats.cost_per_ticket
    assert_equal 2, stats[:tickets]
    assert_equal 3.00, stats[:total].to_f
    assert_equal 1.50, stats[:average].to_f
  end

  test "first-pass rate counts tickets that needed no second implementation run" do
    shipped("TST-D", cost: 1.00)
    shipped("TST-E", cost: 1.00)
    shipped("TST-F", cost: 3.00, implementation_runs: 2) # sent back once

    stats = SpendStats.first_pass
    assert_equal 3, stats[:total]
    assert_equal 2, stats[:clean]
    assert_equal 67, stats[:rate]
    assert_equal 3.00, stats[:rework_cost].to_f, "the reworked ticket's implementation spend"
  end

  test "spend splits by phase and by model, largest first, as percentages" do
    SpendEntry.record!(3.00, source: "phase", phase: "implementation", llm_model: "claude-opus-5")
    SpendEntry.record!(1.00, source: "phase", phase: "review", llm_model: "claude-sonnet-5")

    phases = SpendStats.by_phase
    assert_equal ["implementation", "review"], phases.map { |r| r[:label] }
    assert_equal [75, 25], phases.map { |r| r[:pct] }

    models = SpendStats.by_model
    assert_equal "claude-opus-5", models.first[:label]
    assert_equal 3.00, models.first[:amount].to_f
  end

  test "attention measures time waiting on a person against agent working time" do
    ticket = Ticket.create!(code: "TST-G", title: "gated", state: :ready_to_implement)
    gate = ticket.ticket_gates.create!(to_state: Ticket::STATES[:implementation], reason: "approve?")
    gate.update!(status: "approved") # created_at → updated_at is the wait
    gate.update_columns(created_at: 10.minutes.ago, updated_at: 4.minutes.ago) # 360s

    q = Question.create!(ticket_code: "TST-G", body: "?", options: %w[a b],
                         asked_at: 5.minutes.ago, status: "answered")
    q.update_columns(updated_at: q.asked_at + 120) # 120s

    ticket.phase_runs.create!(phase: "implementation", status: "done", runner: "claude",
                              started_at: 1.hour.ago, duration_s: 480)

    stats = SpendStats.attention
    assert_equal 480, stats[:waiting], "360s gate + 120s question"
    assert_equal 480, stats[:working]
    assert_equal 50, stats[:share], "half the elapsed time was spent waiting on a human"
  end

  test "burn projects today's rate to midnight and flags a cap breach" do
    travel_to Time.current.beginning_of_day + 6.hours do
      SpendEntry.record!(30, source: "phase")
      burn = SpendStats.burn
      assert_equal 30.0, burn[:spent]
      assert_in_delta 120.0, burn[:projected], 0.01, "a quarter of the day gone, so 4x"
      assert burn[:over_cap], "$120 projected against an $80 cap"
    end
  end

  test "everything is nil or empty on a fresh install rather than raising" do
    assert_nil SpendStats.cost_per_ticket
    assert_nil SpendStats.first_pass
    assert_nil SpendStats.attention
    assert_empty SpendStats.by_phase
    assert_equal 0.0, SpendStats.burn[:spent]
  end
end
