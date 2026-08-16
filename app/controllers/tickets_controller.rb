class TicketsController < ApplicationController
  # Manual tickets enter as drafts; "Groom" sends them into the pipeline.
  def create
    title = params[:title].to_s.strip
    if title.present?
      number = Ticket.pluck(:code).filter_map { |c| c[/\d+/]&.to_i }.max.to_i + 1
      code = "ALG-#{number}"
      repo = params[:repo].presence || Workspace.ticket_targets.first || "algo-core"
      Ticket.create!(code: code, title: title, repo: repo, est_label: "—",
                     description: params[:description].to_s.strip.presence,
                     risky: params[:risky] == "1", state: :draft)
      Event.record!(phase_tag: "PLAN", agent_name: "you", ticket_code: code,
                    text: "Drafted #{code} — #{title}")
      PipelineEngine.broadcast
    end
    redirect_to board_path
  end

  def groom
    ticket = Ticket.find_by!(code: params[:code])
    ticket.with_lock do
      if ticket.draft?
        ticket.update!(state: :ready)
        Event.record!(phase_tag: "PLAN", agent_name: "you", ticket_code: ticket.code,
                      text: "#{ticket.code} sent to the pipeline — grooming queued")
      end
    end
    PipelineEngine.broadcast
    back
  end

  def merge
    ticket = Ticket.find_by!(code: params[:code])
    result = BranchMerger.call(ticket)
    if result.ok
      ticket.update!(artifacts: ticket.artifacts | [result.message])
      PipelineEngine.manual_ship!(ticket, result.message)
    else
      Event.record!(phase_tag: "REVIEW", tone: "var(--err)", ticket_code: ticket.code,
                    agent_name: "you", text: "Merge failed: #{result.message}")
      PipelineEngine.broadcast
    end
    back
  end

  def request_changes
    ticket = Ticket.find_by!(code: params[:code])
    feedback = params[:feedback].to_s.strip
    PipelineEngine.request_changes!(ticket, feedback) if feedback.present?
    back
  end

  def phase
    ticket = Ticket.find_by!(code: params[:code])
    case params[:op]
    when "pause"  then @setting.update!(running: false)
    when "resume" then @setting.update!(running: true)
    when "retry"  then retry_run(ticket)
    end
    back
  end

  private

  def retry_run(ticket)
    run = ticket.current_phase_run
    return unless run && run.runner == "claude" && run.status == "failed"

    run.update!(status: "running", started_at: Time.current, finished_at: nil, exit_status: nil)
    unless AgentRunner.start_phase(ticket)
      run.update!(runner: "demo", note: DemoScript.note_for(run.phase))
    end
    PipelineEngine.broadcast
  end
end
