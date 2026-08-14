class SettingsController < ApplicationController
  def autonomy
    value = params[:value].to_s
    @setting.update!(autonomy: value) if Setting::AUTONOMY_MODES.include?(value)
    back
  end

  def toggle_run
    if !@setting.running? && @setting.spend_today >= @setting.spend_cap
      @setting.update!(spend_today: 0)
      Event.record!(phase_tag: "SYS", agent_name: "you", text: "Spend counter reset — new budget window")
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
