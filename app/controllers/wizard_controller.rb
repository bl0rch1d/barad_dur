class WizardController < ApplicationController
  ALLOWED_KEY = /\A(auth|fw|orchestrator_model|harness_dir|map[0-5]|add[0-2]|h[12]|p[12]|repo[0-3]|repo:[\w.\-]+|map:(investigation|planning|implementation|review|testing|deployment))\z/

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
    AgentRoster.rebuild!(@setting)
    @setting.reload.update!(setup_complete: true, running: true)
    Event.record!(phase_tag: "SYS", agent_name: "you",
                  text: "The realm is bound — the watch begins")
    PipelineEngine.broadcast
    redirect_to root_path
  end
end
