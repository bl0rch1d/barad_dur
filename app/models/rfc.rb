class Rfc < ApplicationRecord
  # stage: 0 describe → 1 investigated → 2 clarifying → 3 planned
  STAGES = %w[describe investigate clarify plan].freeze

  def stage_name
    STAGES[stage]
  end

  def advance!
    case stage
    when 0
      update!(stage: 1, trace: RfcScript::TRACE)
      Event.record!(phase_tag: "INVEST", agent_name: "Scout", meta: "38s · 24k tok",
                    text: "Investigating feature request — reading code, specs and git history before proposing anything")
    when 1
      update!(stage: 2, questions: RfcScript::QUESTIONS)
    when 2
      update!(stage: 3, proposals: RfcScript::PROPOSALS)
      Event.record!(phase_tag: "PLAN", agent_name: "Architect", meta: "est 5h 40m",
                    text: "Feature request planned — 5 tickets in dependency order")
    end
  end

  def reset!
    update!(stage: 0, trace: [], questions: [], answers: {}, proposals: [], pushed: false)
  end

  def record_answer!(key, value)
    update!(answers: answers.merge(key.to_s => value))
  end

  def push_to_board!
    return if pushed?

    proposals.each do |p|
      next if Ticket.exists?(code: p["id"])

      Ticket.create!(
        code: p["id"], title: p["title"], repo: p["repo"],
        est_label: "~#{p["est"]}", risky: p["tag"] == "risky",
        state: :ready, dep_codes: Array(p["dep_codes"])
      )
    end
    update!(pushed: true)
    Event.record!(phase_tag: "PLAN", agent_name: "Architect", meta: "est 5h 40m · ~$9.20",
                  text: "#{proposals.size} tickets pushed to board — also wrote spec: risk/venue-exposure-cap")
  end
end
