class PhaseRun < ApplicationRecord
  belongs_to :ticket

  scope :done, -> { where(status: "done") }
  scope :running, -> { where(status: "running") }

  def finish!(at: Time.current)
    secs = started_at ? (at - started_at).to_i : nil
    update!(status: "done", finished_at: at, duration_s: secs)
  end

  def duration_label
    return "running" if status == "running"
    return "—" unless duration_s
    ApplicationController.helpers.short_duration(duration_s)
  end
end
