class RfcsController < ApplicationController
  before_action :require_realm!, only: :show
  ANSWER_KEY = /\Aq\d+\z/

  def show
    @rfc = current_rfc
    @rfc_events = Event.where(ticket_code: "RFC").recent.limit(40).to_a
  end

  def advance
    rfc = current_rfc
    rfc.body = params[:body] if params.key?(:body)
    rfc.save!
    unless rfc.busy?
      if rfc.stage < 2
        # stage 1 = "Investigate" shows as the current step while the run lives
        rfc.update!(stage: 1, job_state: "investigating", error: nil, progress_note: nil)
        RfcInvestigateJob.perform_later(rfc.id)
      else
        rfc.update!(job_state: "planning", error: nil, progress_note: nil)
        RfcPlanJob.perform_later(rfc.id)
      end
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

  def current_rfc
    @current_rfc ||= Rfc.where(pushed: false).order(:id).last || Rfc.new
  end
end
