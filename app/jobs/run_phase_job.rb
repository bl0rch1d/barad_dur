class RunPhaseJob < ApplicationJob
  queue_as :default

  def perform(ticket_id, phase)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket && ticket.state == phase

    run = ticket.current_phase_run
    return unless run && run.runner == "claude" && run.status == "running"

    ClaudeCodeRunner.new(ticket, run).execute
  end
end
