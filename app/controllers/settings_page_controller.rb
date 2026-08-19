# The settings screen. Everything here is scoped to the bound realm — it
# lives in Setting#setup alongside the wizard's answers, so it travels with
# this workspace rather than with the image.
class SettingsPageController < ApplicationController
  before_action :require_realm!, only: :show

  TOGGLES = %w[auto_pr].freeze

  def show; end

  def update
    key = params[:key].to_s
    value = params[:value].to_s

    case key
    when "landing"
      @setting.update!(setup: @setting.setup.merge("landing" => value)) if Features::LANDING_MODES.key?(value)
    when /\Aphase:(#{Ticket::PHASES.join('|')})\z/
      @setting.update!(setup: @setting.setup.merge(key => value == "1" ? "1" : "0"))
    when *TOGGLES
      @setting.update!(setup: @setting.setup.merge(key => value == "1" ? "1" : "0"))
    when "spend_cap"
      cap = value.to_i
      @setting.update!(spend_cap: cap) if cap.between?(1, 10_000)
    when "orchestrator_model"
      @setting.update!(setup: @setting.setup.merge(key => value)) if Setting::ORCHESTRATOR_MODELS.key?(value)
    end

    Workspace.refresh! if key.start_with?("phase:")
    PipelineEngine.broadcast
    redirect_to settings_path
  end
end
