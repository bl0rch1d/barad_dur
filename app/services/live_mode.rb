# Transition between the seeded demo experience and live-workspace mode.
#
# Activation (once, when the wizard finishes with a usable workspace) retires
# the demo dataset: tickets whose repo doesn't resolve in the workspace, all
# demo events/commits/releases/CI/questions/chat, and the simulated spend.
# Agent roles and parsed capabilities are kept. Tickets that target real
# workspace repos survive — they're the user's work.
#
# The optional progress callback receives (stage, done, total, label) so
# LiveModeJob can drive the wizard's step-6 visualization.
class LiveMode
  HISTORY_MODELS = [Event, CommitRecord, Release, CiSuite, Question, ChatMessage, SpendSample, Rfc].freeze

  class << self
    def activate!(setting = Setting.instance, progress: nil)
      return false unless Workspace.available?(setting)
      return true if setting.live_mode?

      # Flip the engine to live FIRST: the ticker must stop fabricating demo
      # work immediately, or it races the purge and re-inserts demo tickets.
      setting.update!(live_mode: true)

      purged, kept = purge_tickets!(setting, progress)
      purge_history!(progress)
      reset_agents!(progress)

      progress&.call("engine", 1, 1, "switching engine to live execution")
      setting.reload
      setting.update!(
        spend_today: 0, tick_count: 0,
        setup: setting.setup.except("live_mode_progress")
                      .merge("live_mode_result" => "#{purged} demo tickets purged · #{kept} workspace tickets kept")
      )
      Event.record!(phase_tag: "SYS", agent_name: "you",
                    text: "Live mode — demo data cleared, workspace #{Workspace.root(setting).basename} is active")
      true
    end

    def deactivate!(setting = Setting.instance)
      setting.update!(live_mode: false)
    end

    private

    def purge_tickets!(setting, progress)
      tickets = Ticket.order(:id).to_a
      purged = 0
      tickets.each_with_index do |ticket, index|
        unless Workspace.repo_path(ticket.repo, setting)
          ticket.destroy
          purged += 1
        end
        progress&.call("tickets", index + 1, tickets.size, "evaluating #{ticket.code}")
      end
      [purged, tickets.size - purged]
    end

    def purge_history!(progress)
      HISTORY_MODELS.each_with_index do |model, index|
        model.delete_all
        progress&.call("history", index + 1, HISTORY_MODELS.size, model.name.underscore.humanize.downcase)
      end
    end

    def reset_agents!(progress)
      agents = Agent.order(:position).to_a
      agents.each_with_index do |agent, index|
        agent.update!(status: "idle", cost_today: 0, doing: "idle — waiting for work")
        progress&.call("agents", index + 1, agents.size, agent.name)
      end
    end
  end
end
