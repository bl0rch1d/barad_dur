class SpecsController < ApplicationController
  before_action :require_realm!, only: :show
  # Kicks off the async parse (SpecSyncJob) unless one is already running.
  def sync
    progress = @setting.setup["spec_sync_progress"]
    unless progress && progress["at"].to_i > 90.seconds.ago.to_i
      @setting.update!(setup: @setting.setup.merge(
        "spec_sync_progress" => { "done" => 0, "total" => 0, "label" => "scanning repositories…", "at" => Time.current.to_i }
      ))
      SpecSyncJob.perform_later
    end
    redirect_back(fallback_location: specs_path)
  end

  def show
    @specs = Capability.ordered.to_a
    @spec = if params[:slug].present?
      Capability.includes(spec_requirements: :spec_scenarios).find_by!(slug: params[:slug])
    else
      @specs[2] || @specs.first
    end
  end
end
