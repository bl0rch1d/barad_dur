# Runs the demo→live transition in the background, publishing staged progress
# into Setting.setup["live_mode_progress"] ({stage, done, total, label, at})
# and broadcasting refreshes so the wizard's step-6 visualization advances.
class LiveModeJob < ApplicationJob
  queue_as :default

  UPDATE_INTERVAL = 0.4

  def perform
    setting = Setting.instance
    last_push = 0.0

    LiveMode.activate!(setting, progress: lambda { |stage, done, total, label|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if stage != "engine" && (now - last_push) < UPDATE_INTERVAL

      last_push = now
      setting.reload
      setting.update!(setup: setting.setup.merge(
        "live_mode_progress" => { "stage" => stage, "done" => done, "total" => total,
                                  "label" => label, "at" => Time.current.to_i }
      ))
      PipelineEngine.broadcast
    })
    PipelineEngine.broadcast
  rescue StandardError => e
    setting = Setting.instance.reload
    setting.update!(setup: setting.setup.except("live_mode_progress")
                                 .merge("live_mode_result" => "activation failed: #{e.message.truncate(80)}"))
    PipelineEngine.broadcast
    raise
  end
end
