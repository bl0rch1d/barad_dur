class DashboardController < ApplicationController
  PHASE_ABBR = {
    "investigation" => "invest", "planning" => "plan", "implementation" => "impl",
    "review" => "review", "testing" => "test", "deployment" => "deploy"
  }.freeze

  def show
    @events = Event.recent.limit(22).to_a
    @gate = Gate.pending.order(:created_at).first
    @questions = Question.pending.order(asked_at: :asc).to_a
    @now_ticket = Ticket.implementation.order(updated_at: :desc).first ||
                  Ticket.in_flight.order(updated_at: :desc).first
    @agents = Agent.ordered.to_a
    @ci = CiSuite.ordered.to_a
    @commits = CommitRecord.recent.limit(6).to_a
    @releases = Release.ordered.limit(3).to_a
    @cycle = CycleStats.rows
    @median = CycleStats.median_label
    @done_count = Ticket.done.count
    @spend_bars = SpendSample.bars
    @stats = build_stats
  end

  private

  def build_stats
    in_flight = Ticket.in_flight.group(:state).count
    flight_sub = Ticket::PHASES.filter_map { |p| in_flight[p] && "#{PHASE_ABBR[p]} #{in_flight[p]}" }
    oldest = @questions.first
    flaky = @ci.count { |c| c.pct < 95 }
    ci_avg = @ci.empty? ? 100 : (@ci.sum(&:pct) / @ci.size)

    [
      { label: "In flight", value: in_flight.values.sum.to_s,
        sub: flight_sub.presence&.join(" · ") || "nothing running", tone: "var(--tx)" },
      { label: "Blocked on you", value: @questions.size.to_s,
        sub: oldest ? "oldest #{oldest.waited_label}" : "all clear",
        tone: @questions.any? ? "var(--warn)" : "var(--tx)" },
      { label: "Cycle time", value: @median, sub: "median, RFC → deploy", tone: "var(--tx)" },
      { label: "Spend today", value: "$#{format('%.2f', @setting.spend_today)}",
        sub: "#{@setting.spend_pct}% of $#{@setting.spend_cap.to_i} cap", tone: "var(--tx)" },
      { label: "CI", value: "#{ci_avg}%",
        sub: flaky.positive? ? "#{flaky} flaky suite#{'s' if flaky > 1}" : "all green",
        tone: ci_avg >= 95 ? "var(--ok)" : "var(--warn)" }
    ]
  end
end
