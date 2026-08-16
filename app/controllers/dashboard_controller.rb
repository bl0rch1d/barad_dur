class DashboardController < ApplicationController
  PHASE_ABBR = {
    "investigation" => "invest", "planning" => "plan", "implementation" => "impl",
    "review" => "review", "testing" => "test", "deployment" => "deploy"
  }.freeze

  def show
    @events = Event.recent.limit(22).to_a
    @board = Ticket.on_board.includes(:agent, :phase_runs, :ticket_gates).to_a
    @gates = Gate.pending.includes(:ticket).order(:created_at).to_a
    @gate = @gates.first
    @questions = Question.pending.order(asked_at: :asc).to_a
    @failed_tickets = @board.select { |t| t.current_phase_run&.status == "failed" }
    @now_ticket = pick_now_ticket
    @agents = Agent.ordered.to_a
    @ci = CiSuite.ordered.to_a
    @recent_runs = if @setting.live_mode?
      PhaseRun.where(runner: "claude").includes(:ticket)
              .order(started_at: :desc).limit(6).to_a
    else
      []
    end
    @commits = @setting.live_mode? ? Workspace.recent_commits(@setting) : CommitRecord.recent.limit(6).to_a
    @releases = Release.ordered.limit(3).to_a
    @cycle = CycleStats.rows
    @median = CycleStats.median_label
    @done_count = Ticket.done.count
    @spend_bars = SpendSample.bars
    @stats = build_stats
  end

  private

  # Prefer the ticket whose live run is actually streaming right now;
  # fall back to the most recently touched in-flight ticket.
  def pick_now_ticket
    live_running = @board.select { |t| t.current_phase_run&.status == "running" && t.live_run? }
    live_running.max_by { |t| t.current_phase_run.updated_at } ||
      @board.select { |t| Ticket::PHASES.include?(t.state) }.max_by(&:updated_at)
  end

  def build_stats
    in_flight = Ticket.in_flight.group(:state).count
    flight_sub = Ticket::PHASES.filter_map { |p| in_flight[p] && "#{PHASE_ABBR[p]} #{in_flight[p]}" }
    blocked_total = @questions.size + @gates.size + @failed_tickets.size
    blocked_parts = [
      @questions.any? ? "#{@questions.size} question#{'s' if @questions.size > 1}" : nil,
      @gates.any? ? "#{@gates.size} gate#{'s' if @gates.size > 1}" : nil,
      @failed_tickets.any? ? "#{@failed_tickets.size} failed" : nil
    ].compact

    tiles = [
      { label: "In flight", value: in_flight.values.sum.to_s,
        sub: flight_sub.presence&.join(" · ") || "nothing running", tone: "var(--tx)" },
      { label: "Blocked on you", value: blocked_total.to_s,
        sub: blocked_parts.presence&.join(" · ") || "all clear",
        tone: blocked_total.positive? ? "var(--warn)" : "var(--tx)" },
      { label: "Cycle time", value: @median, sub: "median, groom → ship", tone: "var(--tx)" },
      { label: "Tribute burned", value: "$#{format('%.2f', @setting.spend_today)}",
        sub: "#{@setting.spend_pct}% of $#{@setting.spend_cap.to_i} cap", tone: "var(--tx)" }
    ]

    tiles << if @setting.live_mode?
      runs = PhaseRun.where(runner: "claude").where(started_at: Time.current.all_day)
      failed = runs.where(status: "failed").count
      { label: "Agent runs", value: runs.count.to_s,
        sub: runs.count.zero? ? "none today" : "#{runs.where(status: 'done').count} done · #{failed} failed",
        tone: failed.positive? ? "var(--warn)" : "var(--ok)" }
    else
      flaky = @ci.count { |c| c.pct < 95 }
      ci_avg = @ci.empty? ? 100 : (@ci.sum(&:pct) / @ci.size)
      { label: "CI", value: "#{ci_avg}%",
        sub: flaky.positive? ? "#{flaky} flaky suite#{'s' if flaky > 1}" : "all green",
        tone: ci_avg >= 95 ? "var(--ok)" : "var(--warn)" }
    end
    tiles
  end
end
