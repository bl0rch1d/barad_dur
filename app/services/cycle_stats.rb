# Cycle-time aggregates for the dashboard, computed from real PhaseRun records.
class CycleStats
  Row = Struct.new(:name, :label, :pct, :tone)

  TONES = {
    "investigation"  => "var(--info)",
    "planning"       => "var(--info)",
    "implementation" => "var(--accent)",
    "review"         => "var(--warn)",
    "testing"        => "var(--warn)",
    "deployment"     => "var(--ok)"
  }.freeze

  def self.rows
    avgs = Ticket::PHASES.index_with do |phase|
      PhaseRun.done.where(phase: phase).where.not(duration_s: nil).average(:duration_s)&.to_f
    end
    max = avgs.values.compact.max || 1.0

    Ticket::PHASES.map do |phase|
      avg = avgs[phase]
      Row.new(
        phase.capitalize,
        avg ? ApplicationController.helpers.short_duration(avg) : "—",
        avg ? ((avg / max) * 100).clamp(4, 100).round : 4,
        TONES[phase]
      )
    end
  end

  def self.median_label
    durations = Ticket.done.where.not(started_at: nil).where.not(finished_at: nil)
                      .pluck(:started_at, :finished_at).map { |s, f| f - s }.sort
    return "—" if durations.empty?

    ApplicationController.helpers.short_duration(durations[durations.size / 2])
  end
end
