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
      reinterpret_vanilla_framework
    end

    private

    # "Vanilla" meant "no harness, use the built-in prompts" back when there
    # was no harness to have. One ships with the app now, so that setting would
    # silently keep six phases on three-line prompts. Reinterpret it once, and
    # say so out loud — a realm whose behaviour changes under it deserves to
    # read why rather than notice later.
    def reinterpret_vanilla_framework
      setting = Setting.first
      return unless setting && setting.setup["fw"] == "2"

      setting.update!(setup: setting.setup.merge("fw" => "1", "fw_was_vanilla" => "1"))
      Event.record!(phase_tag: "SYS", tone: "var(--warn)", agent_name: "system",
                    meta: "framework",
                    text: "This realm was set to vanilla prompts, from before a harness shipped with " \
                          "the app. It now runs #{Harness.bundled&.label || 'the bundled harness'} — " \
                          "switch any phase back to its built-in prompt in Settings.")
    rescue StandardError => e
      Rails.logger.warn { "framework reinterpretation skipped: #{e.class}: #{e.message}" }
    end

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

      return unless setting.setup.key?("spec_sync_progress")

      setting.update!(setup: setting.setup.except("spec_sync_progress")
                                   .merge("last_spec_sync" => "parse interrupted by a restart — run it again"))
    end
  end
end
