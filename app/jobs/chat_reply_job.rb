# Live chat: answers an operator message with a real headless agent run.
# Each room (workspace, or a ticket code) keeps its own session id in
# Setting.setup["chat_session:<room>"], resumed via --resume so the
# conversation keeps its context across messages.
class ChatReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = ChatMessage.find_by(id: message_id)
    return unless message

    setting = Setting.instance
    room = message.room
    session_key = "chat_session:#{room}"
    session_id = setting.setup[session_key]

    harness = Harness.active?(setting) ? Harness.detect(setting) : nil
    chdir = harness&.path || Workspace.root(setting).to_s
    extra_args = ["--add-dir", Workspace.root(setting).to_s]
    extra_args += ["--resume", session_id] if session_id.present?
    prompt = session_id.present? ? message.body : opening_prompt(room, message)

    architect = Agent.for_phase("planning")
    architect&.update!(status: "running", doing: "Discussing #{room} with you")

    result = HeadlessAgent.call(prompt: prompt, chdir: chdir,
                                extra_args: extra_args, max_turns: 15)

    if result.ok
      if result.session_id.present?
        setting.reload
        setting.update!(setup: setting.setup.merge(session_key => result.session_id))
      end
      body = result.result_text.to_s.strip.presence || "(no reply)"
      ChatMessage.create!(room: room, sender: "architect",
                          body: body.truncate(4000), sent_at: Time.current)
      accrue(result, architect)
    else
      ChatMessage.create!(room: room, sender: "architect", sent_at: Time.current,
                          body: "⚠ I couldn't reply: #{result.error.to_s.truncate(200)}")
    end
    architect&.update!(status: "idle", doing: "Last: discussed #{room}")
    PipelineEngine.broadcast
  end

  private

  def opening_prompt(room, message)
    intro = <<~TXT
      You are the Architect agent of an automated SDLC pipeline, in a chat
      thread with the operator. Be concise and concrete. This is a
      conversation: read and reference the workspace freely, but do NOT
      modify any files unless the operator explicitly asks you to.
    TXT
    if (ticket = Ticket.find_by(code: room))
      intro += "\nThread scope: ticket #{ticket.code} — #{ticket.title} [#{ticket.state}], repo #{ticket.repo}."
      intro += "\nOpenspec change: #{PhasePrompts.change_ref(ticket)}" if PhasePrompts.change_ref(ticket)
      intro += "\nTicket description: #{ticket.description}" if ticket.description.present?
      intro += "\nReview feedback: #{ticket.feedback}" if ticket.feedback.present?
    else
      intro += "\nThread scope: the whole workspace."
    end
    "#{intro}\n\nOperator: #{message.body}"
  end

  def accrue(result, architect)
    cost = result.cost.to_f.round(4)
    return unless cost.positive?

    setting = Setting.instance
    setting.update!(spend_today: (setting.spend_today + cost).round(2))
    SpendSample.accrue!(cost)
    architect&.increment!(:cost_today, cost.round(2))
  end
end
