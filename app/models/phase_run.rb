class PhaseRun < ApplicationRecord
  belongs_to :ticket

  scope :done, -> { where(status: "done") }
  scope :running, -> { where(status: "running") }
  # Reached its turn in the pipeline while the tower was stopped: nothing has
  # been spent on it yet and nothing will be until the tower runs again.
  scope :paused, -> { where(status: "paused") }

  def finish!(at: Time.current)
    secs = started_at ? (at - started_at).to_i : nil
    update!(status: "done", finished_at: at, duration_s: secs)
  end

  def paused? = status == "paused"

  def duration_label
    return "paused" if paused?
    return "running" if status == "running"
    return "—" unless duration_s
    ApplicationController.helpers.short_duration(duration_s)
  end
end
