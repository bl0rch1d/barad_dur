# The pipeline engine. Each tick advances in-flight tickets through their
# phases, consults the autonomy setting to decide whether a transition needs a
# human gate, emits events, accrues spend, frees agents and pulls ready work.
#
# The mechanics here are real — DemoScript only supplies the narrative text
# that actual agent runs would produce.
class PipelineEngine
  TICK_BASE_COST = 0.09
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

      setting.increment!(:tick_count)
      in_flight = Ticket.in_flight.includes(:agent).order(:code).to_a
      workable = in_flight.reject { |t| t.gated? || t.blocked_by_question? }
      # live tickets progress when their agent process finishes, not by ticks;
      # in live mode there is no simulated work at all
      demo_workable = setting.live_mode? ? [] : workable.reject(&:live_run?)

      # pulls run before progress so a ticket parked this tick rests visibly
      # in its column until the next tick picks it up
      pull_implementation_work(in_flight.size, setting)
      pull_ready_work(in_flight.size, setting)
      emit_activity(setting, demo_workable)
      demo_workable.each { |ticket| progress(setting, ticket) }
      accrue_spend(setting) if demo_workable.any?
      broadcast
    end

    # Called by ClaudeCodeRunner when a live phase run completes successfully.
    # A run that surfaced clarification questions parks the ticket (Blocked ·
    # clarification) instead of transitioning; answers resume it.
    def phase_finished!(ticket)
      ticket = ticket.reload
      if ticket.blocked_by_question?
        ticket.current_phase_run&.then { |r| r.finish! if r.status == "running" }
        ticket.agent&.update!(status: "waiting", doing: "#{ticket.code} needs your call — see Needs you")
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

      # a live ticket parked on clarification resumes once fully answered
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

    def progress(setting, ticket)
      ticket.increment!(:phase_progress)
      ticket.increment!(:cost, 0.03)
      threshold = Ticket::PHASE_THRESHOLDS.fetch(ticket.state, 5)
      request_transition(setting, ticket) if ticket.phase_progress >= threshold
    end

    def request_transition(setting, ticket)
      next_state = ticket.next_state
      return unless next_state

      if gate_required?(setting, ticket, next_state)
        reason = DemoScript.gate_reason(ticket, next_state, setting.autonomy)
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
        ticket.update!(state: :ready_to_implement, phase_progress: 0)
        ticket.agent&.update!(status: "idle", doing: "Last: groomed #{ticket.code} — #{ticket.title.truncate(40)}")
        Event.record!(phase_tag: "PLAN", ticket: ticket, agent: ticket.agent,
                      meta: ticket.dep_codes.any? ? "deps: #{ticket.dep_codes.join(', ')}" : nil,
                      text: "#{ticket.code} groomed — ready to implement")
      else
        live = AgentRunner.live?(ticket)
        # atomic so a concurrent tick never sees the new state without its run
        ticket.transaction do
          ticket.update!(state: next_state, phase_progress: 0)
          ticket.phase_runs.create!(phase: next_state, status: "running",
                                    runner: live ? "claude" : "demo",
                                    note: live ? "starting claude code run…" : DemoScript.note_for(next_state),
                                    started_at: Time.current)
        end
        ticket.agent&.update!(status: "running", doing: DemoScript.doing_text(ticket))
        Event.record!(phase_tag: DemoScript::TAGS[next_state], ticket: ticket, agent: ticket.agent,
                      text: DemoScript.transition_text(ticket, from, next_state))
        create_commit(ticket) if next_state == "review" && !live
        AgentRunner.start_phase(ticket) if live
      end
    end

    def complete_ticket(ticket)
      ticket.update!(state: :done, finished_at: Time.current, phase_progress: 0)

      if (agent = ticket.agent)
        agent.update!(status: "idle", doing: "Last: shipped #{ticket.code} — #{ticket.title.downcase.truncate(42)}")
      end

      Release.staged&.then { |r| r.update!(lines: r.lines | [ticket.title]) }
      Event.record!(phase_tag: "DEPLOY", ticket: ticket, agent: ticket.agent,
                    meta: "no regressions", text: "#{ticket.code} shipped — staged rollout complete, metrics nominal")
    end

    def create_commit(ticket)
      CommitRecord.create!(
        sha: SecureRandom.hex(4)[0, 7],
        message: DemoScript.commit_message(CommitRecord.count),
        author: ticket.agent&.name || "pipeline",
        committed_at: Time.current
      )
    end

    # ready → investigation (grooming). In demo mode drafts auto-promote;
    # in live mode only user-groomed tickets enter, and only executable ones.
    def pull_ready_work(in_flight_count, setting = Setting.instance)
      return if in_flight_count >= MAX_IN_FLIGHT

      candidates = Ticket.ready.order(:code).to_a
      candidates = [groom_backlog].compact if candidates.empty? && !setting.live_mode?
      ticket = candidates.detect do |t|
        t.deps_satisfied? && !t.gated? && !t.blocked_by_question? &&
          (!setting.live_mode? || AgentRunner.live?(t))
      end
      agent = Agent.idle.ordered.first
      return unless ticket && agent

      start_phase_for(ticket, agent, "investigation", "INVEST", DemoScript.start_text(ticket))
    end

    # ready_to_implement → implementation, dependency- and gate-aware.
    def pull_implementation_work(in_flight_count, setting = Setting.instance)
      return if in_flight_count >= MAX_IN_FLIGHT

      ticket = Ticket.ready_to_implement.order(:code).to_a.detect do |t|
        t.deps_satisfied? && !t.gated? && !t.blocked_by_question? &&
          (!setting.live_mode? || AgentRunner.live?(t))
      end
      return unless ticket

      if gate_required?(setting, ticket, "implementation")
        reason = DemoScript.gate_reason(ticket, "implementation", setting.autonomy)
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
      live = AgentRunner.live?(ticket)
      started = false
      ticket.with_lock do
        next unless ticket.state == expected_state

        ticket.update!(state: phase, agent: agent, phase_progress: 0,
                       started_at: ticket.started_at || Time.current)
        ticket.phase_runs.create!(phase: phase, status: "running",
                                  runner: live ? "claude" : "demo",
                                  note: live ? "starting claude code run…" : DemoScript.note_for(phase),
                                  started_at: Time.current)
        started = true
      end
      return unless started

      agent.update!(status: "running", doing: DemoScript.doing_text(ticket))
      Event.record!(phase_tag: tag, ticket: ticket, agent: agent, text: event_text)
      AgentRunner.start_phase(ticket) if live
    end

    # Keeps the pipeline fed: promote a backlog ticket to ready, or have the
    # demo driver fabricate fresh backlog once the board runs dry.
    def groom_backlog
      candidate = Ticket.draft.order(:code).first || DemoScript.fabricate_backlog_ticket
      return unless candidate

      candidate.update!(state: :ready)
      Event.record!(phase_tag: "PLAN", ticket: candidate, agent_name: "Architect",
                    text: "Groomed #{candidate.code} — estimated and marked ready")
      candidate
    end

    def emit_activity(setting, tickets)
      return if tickets.empty?

      ticket = tickets[setting.tick_count % tickets.size]
      entry = DemoScript.activity_for(ticket, setting.tick_count)
      Event.record!(phase_tag: entry[:tag], ticket: ticket, agent: ticket.agent,
                    meta: entry[:meta], text: entry[:text], cost: 0.02)
    end

    def accrue_spend(setting)
      amount = (TICK_BASE_COST + (setting.tick_count % 3) * 0.03).round(2)
      setting.update!(spend_today: (setting.spend_today + amount).round(2))
      SpendSample.accrue!(amount)
      running = Agent.where(status: "running").to_a
      share = running.empty? ? 0 : (amount / running.size).round(2)
      running.each { |a| a.increment!(:cost_today, share) }
    end

    def pause_for_cap!(setting)
      setting.update!(running: false)
      Event.record!(phase_tag: "SYS", text: "Daily spend cap reached ($#{setting.spend_cap.to_i}) — pipeline paused")
      broadcast
    end
  end
end
