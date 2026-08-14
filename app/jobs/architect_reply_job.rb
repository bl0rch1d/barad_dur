class ArchitectReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = ChatMessage.find_by(id: message_id)
    return unless message

    reply = DemoScript.architect_reply(message)
    ChatMessage.create!(
      room: message.room, sender: "architect",
      body: reply[:body], attach_label: reply[:attach], sent_at: Time.current
    )
    Agent.find_by(name: "Architect")&.update!(status: "running")
    PipelineEngine.broadcast
  end
end
