class RfcsController < ApplicationController
  ANSWER_KEY = /\Aq\d+\z/

  def show
    @rfc = current_rfc
    @rfc_live = live_rfc?
  end

  def advance
    rfc = current_rfc
    rfc.body = params[:body] if params.key?(:body)
    rfc.save!
    if live_rfc?
      advance_live(rfc)
    else
      rfc.advance!
    end
    redirect_to rfc_path
  end

  def answer
    if params[:key].to_s.match?(ANSWER_KEY)
      current_rfc.record_answer!(params[:key], params[:value].to_s)
    end
    redirect_to rfc_path
  end

  def reset
    current_rfc.reset! if current_rfc.persisted?
    redirect_to rfc_path
  end

  def push
    current_rfc.push_to_board!
    PipelineEngine.broadcast
    redirect_to board_path
  end

  private

  def advance_live(rfc)
    return if rfc.busy?

    if rfc.stage < 2
      rfc.update!(job_state: "investigating", error: nil, progress_note: nil)
      RfcInvestigateJob.perform_later(rfc.id)
    else
      rfc.update!(job_state: "planning", error: nil, progress_note: nil)
      RfcPlanJob.perform_later(rfc.id)
    end
  end

  def live_rfc?
    @setting.live_mode? && AgentRunner.live_available?
  end

  def current_rfc
    @current_rfc ||= Rfc.where(pushed: false).order(:id).last || Rfc.new
  end
end
