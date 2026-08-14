class RfcsController < ApplicationController
  ANSWER_KEY = /\Aq\d\z/

  def show
    @rfc = current_rfc
  end

  def advance
    rfc = current_rfc
    rfc.body = params[:body] if params.key?(:body)
    rfc.save!
    rfc.advance!
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
    redirect_to board_path
  end

  private

  def current_rfc
    @current_rfc ||= Rfc.where(pushed: false).order(:id).last || Rfc.new
  end
end
