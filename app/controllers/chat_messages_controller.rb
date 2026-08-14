class ChatMessagesController < ApplicationController
  def create
    body = params[:body].to_s.strip
    if body.present?
      message = ChatMessage.create!(
        room: ActivityController::ROOM, sender: "you", body: body, sent_at: Time.current
      )
      ArchitectReplyJob.set(wait: 1.5.seconds).perform_later(message.id)
    end
    redirect_to activity_path
  end
end
