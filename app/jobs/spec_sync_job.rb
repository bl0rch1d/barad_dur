# Runs the workspace spec parse in the background, publishing progress into
# Setting.setup["spec_sync_progress"] ({done, total, label, at}) and
# broadcasting refreshes so the wizard's progress bar advances live.
class SpecSyncJob < ApplicationJob
  queue_as :default

  UPDATE_INTERVAL = 0.25

  def perform
    setting = Setting.instance
    Workspace.refresh!
    last_push = 0.0

    count = SpecSync.call(setting, progress: lambda { |done, total, label|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if done < total && (now - last_push) < UPDATE_INTERVAL

      last_push = now
      write_progress(setting, done: done, total: total, label: label)
      PipelineEngine.broadcast
    })

    finish(setting, SpecSync.status_summary(setting.reload, count))
  rescue StandardError => e
    finish(setting || Setting.instance, "parse failed: #{e.message.truncate(80)}")
    raise
  end

  private

  def write_progress(setting, done:, total:, label:)
    setting.reload
    setting.update!(setup: setting.setup.merge(
      "spec_sync_progress" => { "done" => done, "total" => total, "label" => label, "at" => Time.current.to_i }
    ))
  end

  def finish(setting, summary)
    setting.reload
    setting.update!(setup: setting.setup.except("spec_sync_progress").merge("last_spec_sync" => summary))
    PipelineEngine.broadcast
  end
end
