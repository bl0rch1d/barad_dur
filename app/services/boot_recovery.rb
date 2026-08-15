# Heals state orphaned by a restart. Async jobs live in the web process's
# memory, so anything they owned is dead after a restart: in-flight RFC
# investigations/plans, spec-parse progress, go-live progress. Runs once at
# web boot (see config/initializers/boot_recovery.rb).
class BootRecovery
  class << self
    def run!
      return unless tables_ready?

      recover_rfcs
      recover_setting_markers
    end

    private

    def tables_ready?
      ActiveRecord::Base.connection.data_source_exists?("rfcs") &&
        ActiveRecord::Base.connection.data_source_exists?("settings")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    def recover_rfcs
      Rfc.where(job_state: %w[investigating planning]).find_each do |rfc|
        rfc.update!(job_state: "failed", progress_note: nil,
                    error: "interrupted by an app restart — click Retry")
        Event.record!(phase_tag: rfc.stage >= 2 ? "PLAN" : "INVEST", tone: "var(--err)",
                      agent_name: "system", ticket_code: "RFC",
                      text: "RFC run was interrupted by a restart — it can be retried")
      end
    end

    def recover_setting_markers
      setting = Setting.first
      return unless setting

      stale = setting.setup.slice("spec_sync_progress", "live_mode_progress")
      return if stale.empty?

      cleaned = setting.setup.except("spec_sync_progress", "live_mode_progress")
      if stale.key?("spec_sync_progress")
        cleaned = cleaned.merge("last_spec_sync" => "parse interrupted by a restart — run it again")
      end
      if stale.key?("live_mode_progress") && !setting.live_mode?
        cleaned = cleaned.merge("live_mode_result" => "activation interrupted by a restart — start again")
      end
      setting.update!(setup: cleaned)
    end
  end
end
