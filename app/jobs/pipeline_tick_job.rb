class PipelineTickJob < ApplicationJob
  queue_as :default

  def perform
    PipelineEngine.tick!
  end
end
