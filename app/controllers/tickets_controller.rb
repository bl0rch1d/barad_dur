class TicketsController < ApplicationController
  # Manual tickets enter as drafts; "Groom" sends them into the pipeline.
  def create
    title = params[:title].to_s.strip
    if title.present?
      number = Ticket.pluck(:code).filter_map { |c| c[/\d+/]&.to_i }.max.to_i + 1
      code = "ALG-#{number}"
      # clamp to what the wizard selected — a stale form must not file work
      # into a repo the pipeline doesn't own
      targets = Workspace.selected_ticket_targets
      repo = targets.include?(params[:repo]) ? params[:repo] : targets.first || "workspace"
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

  def update
    ticket = Ticket.find_by!(code: params[:code])
    return back unless ticket.editable?

    attrs = {}
    attrs[:title] = params[:title].to_s.strip if params[:title].to_s.strip.present?
    attrs[:description] = params[:description].to_s.strip.presence if params.key?(:description)
    if params[:repo].present? && ([ticket.repo] + Workspace.selected_ticket_targets).include?(params[:repo])
      attrs[:repo] = params[:repo]
    end
    attrs[:est_label] = params[:est_label].to_s.strip.presence || "—" if params.key?(:est_label)
    attrs[:risky] = params[:risky] == "1" if params.key?(:risky)
    if params.key?(:dep_codes)
      wanted = params[:dep_codes].to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
      attrs[:dep_codes] = wanted & Ticket.where.not(code: ticket.code).pluck(:code)
    end
    ticket.update!(attrs)
    Event.record!(phase_tag: "PLAN", agent_name: "you", ticket_code: ticket.code,
                  text: "#{ticket.code} edited")
    PipelineEngine.broadcast
    back
  end

  def destroy
    ticket = Ticket.find_by!(code: params[:code])
    return back unless ticket.deletable?

    code = ticket.code
    Question.where(ticket_code: code).delete_all
    ticket.destroy
    Event.record!(phase_tag: "SYS", agent_name: "you", ticket_code: code,
                  text: "#{code} deleted")
    PipelineEngine.broadcast
    redirect_to board_path
  end

  def enrich
    ticket = Ticket.find_by!(code: params[:code])
    marker = @setting.setup["enrich:#{ticket.code}"]
    unless marker && marker.to_i > 5.minutes.ago.to_i
      @setting.update!(setup: @setting.setup.merge("enrich:#{ticket.code}" => Time.current.to_i))
      TicketEnrichJob.perform_later(ticket.id)
    end
    back
  end

  def push_pr
    ticket = Ticket.find_by!(code: params[:code])
    PushPrJob.perform_later(ticket.id)
    Event.record!(phase_tag: "DEPLOY", ticket_code: ticket.code, agent_name: "you",
                  text: "Pushing #{ticket.code} to origin and opening a PR…")
    PipelineEngine.broadcast
    back
  end

  # Lands the work the way this realm is configured to: merge the pull
  # request, merge locally, or simply mark it shipped.
  def merge
    ticket = Ticket.find_by!(code: params[:code])
    ticket.ticket_gates.pending.update_all(status: "approved")
    LandWork.call(ticket)
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
    when "restart" then PipelineEngine.restart!(ticket)
    end
    back
  end

  private

  def retry_run(ticket)
    run = ticket.current_phase_run
    return unless run && run.runner == "claude" && run.status == "failed"

    run.update!(status: "running", started_at: Time.current, finished_at: nil, exit_status: nil)
    unless AgentRunner.start_phase(ticket)
      # runner unavailable (CLI/auth/repo missing) — surface it, stay failed
      run.update!(status: "failed", finished_at: Time.current,
                  note: "runner unavailable — check auth and workspace")
    end
    PipelineEngine.broadcast
  end
end
