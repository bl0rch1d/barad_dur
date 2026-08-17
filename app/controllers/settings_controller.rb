class SettingsController < ApplicationController
  def autonomy
    value = params[:value].to_s
    @setting.update!(autonomy: value) if Setting::AUTONOMY_MODES.include?(value)
    back
  end

  def toggle_run
    if !@setting.running? && @setting.over_cap?
      @setting.override_cap_for_today!
      Event.record!(phase_tag: "SYS", agent_name: "you", text: "Spend cap overridden for today — the forge burns on")
    end
    @setting.update!(running: !@setting.running)
    Event.record!(phase_tag: "SYS", agent_name: "you",
                  text: @setting.running ? "Pipeline resumed" : "Pipeline paused")
    PipelineEngine.broadcast
    back
  end

  def stop
    if @setting.running?
      @setting.update!(running: false)
      Event.record!(phase_tag: "SYS", agent_name: "you", text: "Pipeline stopped")
      PipelineEngine.broadcast
    end
    back
  end
end
