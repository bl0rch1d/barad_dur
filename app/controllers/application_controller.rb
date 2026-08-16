class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :load_shared

  private

  def load_shared
    @setting = Setting.instance
    @board_count = Ticket.on_board.count
    @agents_running = Agent.where(status: "running").count
    @spend_bars = SpendSample.bars
    @attention_count = attention_count

    if params[:ticket].present?
      @drawer_ticket = Ticket.includes(:agent, :phase_runs).find_by(code: params[:ticket])
    end
    @wizard_step = params[:wizard].to_i.clamp(1, 5) if params[:wizard].present?
  end

  def current_theme
    %w[dark light].include?(cookies[:theme]) ? cookies[:theme] : "dark"
  end
  helper_method :current_theme

  def back
    redirect_back(fallback_location: root_path)
  end

  # Everything currently waiting on the operator — drives the tab-title and
  # favicon attention badge.
  def attention_count
    failed = Ticket.on_board.includes(:phase_runs).count { |t| t.current_phase_run&.status == "failed" }
    Question.pending.count + Gate.pending.count + failed
  end
end
