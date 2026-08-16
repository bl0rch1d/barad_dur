# The pipeline engine. Each tick sweeps dead runs and pulls waiting tickets
# into execution — grooming (ready → investigation) and building
# (ready_to_implement → implementation) — honoring dependencies, gates,
# clarification questions and the daily spend cap. Phase progression itself
# is event-driven: ClaudeCodeRunner calls back on completion.
class PipelineEngine
  MAX_IN_FLIGHT = 5

  class << self
    def tick!
      setting = Setting.instance
      sweep_stale_runs!
      return unless setting.running?

      if setting.spend_today >= setting.spend_cap
        pause_for_cap!(setting)
        return
      end

      in_flight = Ticket.in_flight.count
      pull_implementation_work(in_flight, setting)
      pull_ready_work(in_flight, setting)
      broadcast
    end

    # Called by ClaudeCodeRunner when a live phase run completes successfully.
    # A run that surfaced clarification questions parks the ticket (Blocked ·
    # clarification) instead of transitioning; answers resume it.
    def phase_finished!(ticket)
      ticket = ticket.reload
      if ticket.blocked_by_question?
        ticket.current_phase_run&.then { |r| r.finish! if r.status == "running" }
        ticket.agent&.update!(status: "waiting", doing: "#{ticket.code} needs your call — see The Eye demands")
      else
        request_transition(Setting.instance, ticket)
      end
      broadcast
    end

    def approve_gate!(gate)
      return unless gate.status == "pending"

      gate.update!(status: "approved")
      apply_transition(gate.ticket)
      broadcast
    end

    def answer_question!(question, option)
      question.answer!(option)
      Event.record!(phase_tag: "GATE", ticket_code: question.ticket_code, agent_name: "you",
                    meta: question.phase, text: "Decision recorded: #{option} — agent unblocked")
      Agent.where(status: "waiting").update_all(status: "running")

      # a ticket parked on clarification resumes once fully answered
      ticket = Ticket.find_by(code: question.ticket_code)
      if ticket && !ticket.blocked_by_question? &&
         Ticket::PHASES.include?(ticket.state) && ticket.current_phase_run&.status == "done"
        request_transition(Setting.instance, ticket)
      end
      broadcast
    end

    def broadcast
      Turbo::StreamsChannel.broadcast_refresh_to(:app)
    rescue => e
      Rails.logger.debug { "pipeline broadcast skipped: #{e.message}" }
    end

    # The user approved & merged from the drawer — the human takes over from
    # here, so the ticket completes regardless of remaining phases.
    def manual_ship!(ticket, message)
      ticket.with_lock do
        return if ticket.done?

        ticket.current_phase_run&.then { |r| r.finish! if r.status == "running" }
        ticket.update!(state: :done, finished_at: Time.current)
      end
      ticket.agent&.update!(status: "idle", doing: "Last: shipped #{ticket.code} — approved & merged")
      Release.staged&.then { |r| r.update!(lines: r.lines | [ticket.title]) }
      Event.record!(phase_tag: "DEPLOY", ticket: ticket, agent: ticket.agent, meta: "manual",
                    text: "#{ticket.code} approved & merged — #{message}")
      broadcast
    end

    # The user requested changes from the drawer: the ticket goes back to
    # implementation with the feedback wired into the agent's prompt.
    def request_changes!(ticket, feedback)
      ticket.with_lock do
        ticket.current_phase_run&.then { |r| r.finish! if r.status == "running" }
        ticket.update!(state: :implementation, feedback: feedback)
        ticket.phase_runs.create!(phase: "implementation", status: "running", runner: "claude",
                                  note: "rework: #{feedback.truncate(60)}", started_at: Time.current)
      end
      agent = ticket.agent || Agent.idle.ordered.first
      ticket.update!(agent: agent) if agent && ticket.agent.nil?
      agent&.update!(status: "running", doing: "#{ticket.code} rework: #{feedback.truncate(50)}")
      Event.record!(phase_tag: "REVIEW", tone: "var(--warn)", ticket: ticket, agent: agent,
                    meta: "changes requested",
                    text: "Changes requested on #{ticket.code}: #{feedback.truncate(120)}")
      AgentRunner.start_phase(ticket)
      broadcast
    end

    # Live phase runs whose process died (restart, crash) never finish and
    # would freeze their ticket forever. A healthy run touches its record
    # continuously while streaming; one silent past the CLI timeout is dead.
    def sweep_stale_runs!
      cutoff = (Float(ENV.fetch("CLAUDE_TIMEOUT", 900)) + 120).seconds.ago
      PhaseRun.where(runner: "claude", status: "running")
              .where(updated_at: ...cutoff).find_each do |run|
        run.update!(status: "failed", finished_at: Time.current)
        Event.record!(phase_tag: "SYS", tone: "var(--err)", ticket: run.ticket,
                      meta: run.phase,
                      text: "#{run.ticket.code} #{run.phase} run went silent — likely interrupted; retry from the ticket drawer")
      end
    end

    private

    def request_transition(setting, ticket)
      next_state = ticket.next_state
      return unless next_state

      if gate_required?(setting, ticket, next_state)
        reason = PipelineText.gate_reason(ticket, next_state, setting.autonomy)
        ticket.ticket_gates.create!(to_state: Ticket::STATES[next_state.to_sym], reason: reason)
        Event.record!(phase_tag: "GATE", ticket: ticket, agent: ticket.agent,
                      meta: setting.autonomy, text: "Gated: #{reason}")
      else
        apply_transition(ticket)
      end
    end

    def gate_required?(setting, ticket, next_state)
      return false unless Ticket::PHASES.include?(next_state)

      case setting.autonomy
      when "every"
        true
      when "risky"
        next_state == "deployment" ||
          (ticket.risky? && %w[implementation testing deployment].include?(next_state))
      else
        false
      end
    end

    def apply_transition(ticket)
      from = ticket.state
      next_state = ticket.next_state
      return unless next_state

      ticket.current_phase_run&.then { |r| r.finish! if r.status == "running" }

      if next_state == "done"
        complete_ticket(ticket)
      elsif next_state == "ready_to_implement"
        # grooming complete — park the ticket and free its agent; the engine
        # picks it up for implementation once its dependencies are done
        ticket.update!(state: :ready_to_implement)
        ticket.agent&.update!(status: "idle", doing: "Last: groomed #{ticket.code} — #{ticket.title.truncate(40)}")
        Event.record!(phase_tag: "PLAN", ticket: ticket, agent: ticket.agent,
                      meta: ticket.dep_codes.any? ? "deps: #{ticket.dep_codes.join(', ')}" : nil,
                      text: "#{ticket.code} groomed — ready to implement")
      else
        ticket.transaction do
          ticket.update!(state: next_state)
          ticket.phase_runs.create!(phase: next_state, status: "running", runner: "claude",
                                    note: "starting claude code run…", started_at: Time.current)
        end
        ticket.agent&.update!(status: "running", doing: PipelineText.doing_text(ticket))
        Event.record!(phase_tag: PipelineText::TAGS[next_state], ticket: ticket, agent: ticket.agent,
                      text: PipelineText.transition_text(ticket, from, next_state))
        AgentRunner.start_phase(ticket)
      end
    end

    def complete_ticket(ticket)
      ticket.update!(state: :done, finished_at: Time.current)

      if (agent = ticket.agent)
        agent.update!(status: "idle", doing: "Last: shipped #{ticket.code} — #{ticket.title.downcase.truncate(42)}")
      end

      Release.staged&.then { |r| r.update!(lines: r.lines | [ticket.title]) }
      Event.record!(phase_tag: "DEPLOY", ticket: ticket, agent: ticket.agent,
                    text: "#{ticket.code} finished the pipeline — ready to merge from the drawer")
    end

    # ready → investigation (grooming): only tickets an agent can execute.
    def pull_ready_work(in_flight_count, setting = Setting.instance)
      return if in_flight_count >= MAX_IN_FLIGHT

      ticket = Ticket.ready.order(:code).to_a.detect do |t|
        t.deps_satisfied? && !t.gated? && !t.blocked_by_question? && AgentRunner.live?(t)
      end
      agent = Agent.idle.ordered.first
      return unless ticket && agent

      start_phase_for(ticket, agent, "investigation", "INVEST", PipelineText.start_text(ticket))
    end

    # ready_to_implement → implementation, dependency- and gate-aware.
    def pull_implementation_work(in_flight_count, setting = Setting.instance)
      return if in_flight_count >= MAX_IN_FLIGHT

      ticket = Ticket.ready_to_implement.order(:code).to_a.detect do |t|
        t.deps_satisfied? && !t.gated? && !t.blocked_by_question? && AgentRunner.live?(t)
      end
      return unless ticket

      if gate_required?(setting, ticket, "implementation")
        reason = "#{ticket.code} is ready#{' (risky)' if ticket.risky?} — approve to start implementation."
        ticket.ticket_gates.create!(to_state: Ticket::STATES[:implementation], reason: reason)
        Event.record!(phase_tag: "GATE", ticket: ticket, meta: setting.autonomy, text: "Gated: #{reason}")
        return
      end

      agent = Agent.idle.ordered.first
      return unless agent

      start_phase_for(ticket, agent, "implementation", "IMPL",
                      "#{ticket.code} picked up for implementation")
    end

    # Locked pickup: the web process (groom clicks, RFC pushes) and the ticker
    # race on the same rows — re-check state under the row lock.
    def start_phase_for(ticket, agent, phase, tag, event_text)
      expected_state = phase == "investigation" ? "ready" : "ready_to_implement"
      started = false
      ticket.with_lock do
        next unless ticket.state == expected_state

        ticket.update!(state: phase, agent: agent,
                       started_at: ticket.started_at || Time.current)
        ticket.phase_runs.create!(phase: phase, status: "running", runner: "claude",
                                  note: "starting claude code run…", started_at: Time.current)
        started = true
      end
      return unless started

      agent.update!(status: "running", doing: PipelineText.doing_text(ticket))
      Event.record!(phase_tag: tag, ticket: ticket, agent: agent, text: event_text)
      AgentRunner.start_phase(ticket)
    end

    def pause_for_cap!(setting)
      setting.update!(running: false)
      Event.record!(phase_tag: "SYS", text: "Daily spend cap reached ($#{setting.spend_cap.to_i}) — the forge is quenched")
      broadcast
    end
  end
end
