# Heal job-owned state orphaned by the previous shutdown (async jobs die
# with the web process). Server boot only — consoles/rake tasks skip it.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless defined?(Rails::Server) || ENV["BOOT_RECOVERY"] == "on"

  BootRecovery.run!
rescue StandardError => e
  Rails.logger.warn("boot recovery skipped: #{e.class}: #{e.message}")
end
