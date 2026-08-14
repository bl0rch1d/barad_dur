namespace :pipeline do
  desc "Run the pipeline tick loop (blocking; the ticker service runs this)"
  task ticker: :environment do
    $stdout.sync = true
    interval = Float(ENV.fetch("PIPELINE_TICK_INTERVAL", 3.2))
    Rails.logger.info("pipeline ticker: ticking every #{interval}s")
    puts "pipeline ticker: ticking every #{interval}s"

    loop do
      sleep interval
      Rails.application.reloader.wrap { PipelineEngine.tick! }
    rescue Interrupt
      break
    rescue => e
      # e.g. the web service is still creating/migrating the database — retry
      Rails.logger.warn("pipeline ticker: #{e.class}: #{e.message}")
    end
  end
end
