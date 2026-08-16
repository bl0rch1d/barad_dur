class ChatMessagesController < ApplicationController
  def create
    room = params[:room].presence || ActivityController::WORKSPACE_ROOM
    body = params[:body].to_s.strip

    if body.present?
      message = ChatMessage.create!(room: room, sender: "you", body: body, sent_at: Time.current)
      ChatReplyJob.perform_later(message.id)
      PipelineEngine.broadcast
    end
    redirect_to activity_path(room: room)
  end
end
