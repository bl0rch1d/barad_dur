# Builds the pipeline's agent roster. With a harness present, each phase is
# staffed by the matching harness agent (explorer→investigation, planner→
# planning, reviewer/critic→review, …); phases without a match keep the
# built-in defaults. Remaining harness agents are delegation specialists —
# they're spawned inside runs, never assigned tickets, and are rendered
# straight from the harness scan.
class AgentRoster
  DEFAULTS = {
    "investigation"  => { name: "Scout",     abbr: "SC", tools: ["ripgrep", "git log", "trace"] },
    "planning"       => { name: "Architect", abbr: "AR", tools: ["openspec", "dep graph", "tickets"] },
    "implementation" => { name: "Builder",   abbr: "BD", tools: ["editor", "shell", "patch"] },
    "review"         => { name: "Critic",    abbr: "CR", tools: ["diff reader", "spec check"] },
    "testing"        => { name: "Tester",    abbr: "TS", tools: ["test runner", "coverage"] },
    "deployment"     => { name: "Shipper",   abbr: "SH", tools: ["git merge", "changelog"] }
  }.freeze

  class << self
    # One agent per pipeline phase, harness-mapped where possible. Updates
    # rows in place (tickets hold FKs); surplus rows are detached + removed.
    def rebuild!(setting = Setting.instance)
      harness = Harness.active?(setting) ? Harness.detect(setting) : nil
      model_label = Setting::ORCHESTRATOR_MODELS[setting.orchestrator_model].to_s.downcase.presence || "opus 5"
      used = []

      desired = Ticket::PHASES.each_with_index.map do |phase, position|
        harness_name = harness && (Harness.phase_agents(phase, setting) - used).first
        used << harness_name if harness_name
        default = DEFAULTS[phase]
        {
          name: harness_name || default[:name],
          abbr: harness_name ? abbr_for(harness_name) : default[:abbr],
          role: phase, llm_model: model_label, position: position,
          tools: harness_name ? ["#{harness.repo} · .claude/agents"] : default[:tools],
          status: "idle", doing: "idle — waiting for work"
        }
      end

      existing = Agent.order(:position, :id).to_a
      kept = desired.map.with_index do |attrs, index|
        agent = existing[index] || Agent.new
        agent.assign_attributes(attrs)
        agent.save!
        agent
      end

      extras = Agent.where.not(id: kept.map(&:id))
      Ticket.where(agent_id: extras.select(:id)).update_all(agent_id: nil)
      extras.destroy_all
      kept
    end

    def specialists(setting = Setting.instance)
      harness = Harness.detect(setting)
      return [] unless harness

      roster_names = Agent.pluck(:name).map(&:downcase)
      harness.agent_details.reject { |a| roster_names.include?(a[:name].downcase) }
    end

    private

    def abbr_for(name)
      parts = name.split(/[-_]/)
      (parts.size > 1 ? parts.first(2).map { |p| p[0] }.join : name[0, 2]).upcase
    end
  end
end
