class Rfc < ApplicationRecord
  # stage: 0 describe → 1 investigated → 2 clarifying → 3 planned
  STAGES = %w[describe investigate clarify plan].freeze

  def stage_name
    STAGES[stage]
  end

  def reset!
    update!(stage: 0, trace: [], questions: [], answers: {}, proposals: [],
            pushed: false, job_state: "idle", error: nil, progress_note: nil)
  end

  def busy?
    %w[investigating planning].include?(job_state)
  end

  def record_answer!(key, value)
    update!(answers: answers.merge(key.to_s => value))
  end

  # Creates tickets from the proposals: codes are allocated here, and each
  # proposal's depends_on indexes are resolved to the allocated codes.
  def push_to_board!
    return if pushed? || proposals.empty?

    next_number = Ticket.pluck(:code).filter_map { |c| c[/\d+/]&.to_i }.max.to_i
    codes = proposals.map { |p| p["id"].presence || "ALG-#{next_number += 1}" }

    proposals.each_with_index do |p, i|
      next if Ticket.exists?(code: codes[i])

      deps = p["dep_codes"].presence ||
             Array(p["dep_indexes"]).map { |di| codes[di.to_i - 1] }.compact
      est = p["est"].to_s
      artifacts = p["change"].present? ? ["openspec change: #{p['change']}"] : []
      # investigation + planning already happened in the RFC flow — these
      # tickets land ready to implement, not at the start of the pipeline
      Ticket.create!(
        code: codes[i], title: p["title"], repo: p["repo"],
        est_label: est.start_with?("~") ? est : "~#{est}",
        risky: p["risky"] == true || p["tag"] == "risky",
        description: p["summary"].presence,
        acceptance_criteria: Array(p["acceptance_criteria"]),
        state: :ready_to_implement, dep_codes: deps, artifacts: artifacts
      )
    end
    update!(pushed: true)
    Event.record!(phase_tag: "PLAN", agent_name: "Architect", meta: "ready to implement",
                  text: "#{proposals.size} tickets pushed to board")
  end
end
