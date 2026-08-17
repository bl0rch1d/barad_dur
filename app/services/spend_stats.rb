# Analytics derived from the spend ledger and the run history. Everything
# here is a query — there are no rollup tables to fall out of step, and at a
# few thousand rows there is no reason for any.
class SpendStats
  WINDOW = 30.days

  class << self
    # What a finished ticket actually costs, end to end. The single most
    # useful number here: the unit economics of the whole pipeline.
    def cost_per_ticket
      done = Ticket.done.where.not(finished_at: nil).where(finished_at: WINDOW.ago..)
      codes = done.pluck(:code)
      return nil if codes.empty?

      total = SpendEntry.where(ticket_code: codes).sum(:amount)
      { tickets: codes.size, total: total, average: total / codes.size }
    end

    # Work sent back after review, and what that rework cost. A ticket that
    # needed more than one implementation run did not pass first time.
    def first_pass
      done = Ticket.done.where(finished_at: WINDOW.ago..).includes(:phase_runs).to_a
      return nil if done.empty?

      reworked = done.select { |t| t.phase_runs.count { |r| r.phase == "implementation" } > 1 }
      wasted = reworked.any? ? SpendEntry.where(ticket_code: reworked.map(&:code), phase: "implementation").sum(:amount) : 0
      { total: done.size, clean: done.size - reworked.size,
        rate: ((done.size - reworked.size) * 100.0 / done.size).round,
        rework_cost: wasted }
    end

    # Where the money goes, by pipeline phase and by model. Comparing models
    # is what turns the orchestrator setting from a guess into a decision.
    def by_phase
      grouped(SpendEntry.where(occurred_at: WINDOW.ago..).where.not(phase: nil).group(:phase).sum(:amount))
    end

    def by_model
      grouped(SpendEntry.where(occurred_at: WINDOW.ago..).where.not(llm_model: nil).group(:llm_model).sum(:amount))
    end

    def by_source
      grouped(SpendEntry.where(occurred_at: WINDOW.ago..).group(:source).sum(:amount))
    end

    # How long tickets waited on a human versus how long agents actually
    # worked. This is the number that says whether you are the bottleneck.
    def attention
      waiting = gate_wait + question_wait
      working = PhaseRun.where(started_at: WINDOW.ago..).sum(:duration_s).to_i
      return nil if waiting.zero? && working.zero?

      { waiting: waiting, working: working,
        share: (waiting + working).positive? ? (waiting * 100.0 / (waiting + working)).round : 0 }
    end

    # Today's burn so far, and where it lands by midnight at this rate.
    def burn
      setting = Setting.instance
      spent = setting.spend_today.to_f
      elapsed = (Time.current - Time.current.beginning_of_day).to_f
      projected = elapsed.positive? ? spent * (86_400.0 / elapsed) : 0
      { spent: spent, cap: setting.spend_cap.to_f, projected: projected,
        over_cap: projected > setting.spend_cap.to_f && setting.spend_cap.positive? }
    end

    private

    # pct is the share of the total (for the "88% · 6%" footers); bar is
    # scaled against the largest row so the widest one fills its track.
    def grouped(totals)
      total = totals.values.sum
      return [] if total.zero?

      max = totals.values.max
      totals.sort_by { |_, v| -v }.map do |label, amount|
        { label: label, amount: amount,
          pct: (amount * 100.0 / total).round,
          bar: (amount * 100.0 / max).round }
      end
    end

    # Approved gates and answered questions carry their decision time in
    # updated_at; the gap from when they were raised is time spent waiting
    # on a person.
    def gate_wait
      Gate.where.not(status: "pending").where(created_at: WINDOW.ago..)
          .pluck(:created_at, :updated_at).sum { |a, b| (b - a).to_i }
    end

    def question_wait
      Question.where.not(status: "pending").where(asked_at: WINDOW.ago..)
              .pluck(:asked_at, :updated_at).sum { |a, b| (b - a).to_i }
    end
  end
end
