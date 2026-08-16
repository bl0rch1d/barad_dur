class ActivityController < ApplicationController
  DEMO_ROOM = "ALG-215".freeze
  WORKSPACE_ROOM = "workspace".freeze
  ROOM = DEMO_ROOM # legacy demo constant (ChatMessagesController fallback)

  def show
    if @setting.live_mode?
      @rooms = [WORKSPACE_ROOM] +
               Ticket.on_board.order(:code).limit(10).pluck(:code)
      @room = @rooms.include?(params[:room]) ? params[:room] : WORKSPACE_ROOM
    else
      @rooms = [DEMO_ROOM]
      @room = DEMO_ROOM
    end

    @messages = ChatMessage.in_room(@room).to_a
    @events = if @room == WORKSPACE_ROOM || @room == DEMO_ROOM
      Event.recent.limit(30).to_a
    else
      Event.where(ticket_code: @room).recent.limit(30).to_a
    end
    # a fresh user message with no reply yet → show the thinking indicator
    @awaiting_reply = @messages.last&.from_user? && @messages.last.sent_at > 3.minutes.ago
  end
end
