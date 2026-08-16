class ChatMessagesController < ApplicationController
  def create
    live = @setting.live_mode? && AgentRunner.live_available?
    room = params[:room].presence || (live ? ActivityController::WORKSPACE_ROOM : ActivityController::DEMO_ROOM)
    body = params[:body].to_s.strip

    if body.present?
      message = ChatMessage.create!(room: room, sender: "you", body: body, sent_at: Time.current)
      if live
        ChatReplyJob.perform_later(message.id)
      else
        ArchitectReplyJob.set(wait: 1.5.seconds).perform_later(message.id)
      end
      PipelineEngine.broadcast
    end
    redirect_to activity_path(room: room)
  end
end
