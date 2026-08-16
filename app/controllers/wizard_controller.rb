class WizardController < ApplicationController
  ALLOWED_KEY = /\A(auth|fw|orchestrator_model|map[0-5]|add[0-2]|h[12]|p[12]|repo[0-3]|repo:[\w.\-]+|map:(investigation|planning|implementation|review|testing|deployment))\z/

  WORKSPACE_DIR_VALUE = %r{\A[\w.\- /]{0,200}\z}

  def patch
    key = params[:key].to_s
    value = params[:value].to_s
    if key == "workspace_dir"
      if value.match?(WORKSPACE_DIR_VALUE) && !value.include?("..") && !value.start_with?("/")
        Workspace.refresh!
        @setting.update!(setup: @setting.setup.merge(key => value))
      end
    elsif key.match?(ALLOWED_KEY)
      @setting.update!(setup: @setting.setup.merge(key => value))
    end
    back
  end

  def finish
    if Workspace.available?(@setting) && !@setting.live_mode?
      # go-live is asynchronous: step 6 visualizes LiveModeJob's progress
      progress = @setting.setup["live_mode_progress"]
      unless progress && progress["at"].to_i > 90.seconds.ago.to_i
        @setting.update!(setup: @setting.setup.merge(
          "live_mode_progress" => { "stage" => "tickets", "done" => 0, "total" => 0,
                                    "label" => "starting…", "at" => Time.current.to_i }
        ))
        # slight head start for the browser's navigation to step 6, so the
        # user watches the transition from its first stage
        LiveModeJob.set(wait: 0.7.seconds).perform_later
      end
      @setting.reload.update!(setup_complete: true, running: true)
      redirect_to root_path(wizard: 6)
    elsif @setting.live_mode?
      # already live — show the step-6 summary instead of silently bouncing home
      @setting.update!(setup_complete: true, running: true)
      redirect_to root_path(wizard: 6)
    else
      LiveMode.deactivate!(@setting)
      @setting.reload.update!(setup_complete: true, running: true)
      Event.record!(phase_tag: "SYS", agent_name: "you", text: "Setup complete — pipeline started")
      PipelineEngine.broadcast
      redirect_to root_path
    end
  end
end
