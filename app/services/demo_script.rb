# Flavor content for the demo driver. The engine's mechanics (state machine,
# gates, phase runs, spend) are real; this module supplies the narrative text a
# real agent harness would produce. Swapping this out for actual agent output
# is the intended integration point.
module DemoScript
  TAGS = {
    "investigation"  => "INVEST",
    "planning"       => "PLAN",
    "implementation" => "IMPL",
    "review"         => "REVIEW",
    "testing"        => "TEST",
    "deployment"     => "DEPLOY"
  }.freeze

  PHASE_NOTES = {
    "investigation"  => "traced 14 call sites, 3 candidate root causes",
    "planning"       => "spec delta + 5 subtasks, deps resolved",
    "implementation" => "patch in progress on branch pipe/alg",
    "review"         => "critic pass: 2 comments resolved",
    "testing"        => "41 unit · 6 integration · property suite",
    "deployment"     => "tag, changelog entry, staged rollout"
  }.freeze

  ACTIVITY = {
    "investigation" => [
      { tag: "INVEST", text: "Reproduced the issue on a replay window",            meta: "evidence: 4 traces" },
      { tag: "INVEST", text: "Bisected regression to the fee model refactor",      meta: "confidence 0.81" },
      { tag: "SPEC",   text: "Cross-checked behaviour against openspec scenarios", meta: "spec delta" }
    ],
    "planning" => [
      { tag: "PLAN", text: "Split work into venue adapter + policy layer",     meta: "5 subtasks · 2 deps" },
      { tag: "PLAN", text: "Resolved dependency order against open tickets",   meta: "dep graph" },
      { tag: "SPEC", text: "Drafted spec delta for the affected capability",   meta: "openspec" }
    ],
    "implementation" => [
      { tag: "IMPL", text: "Wrote reconciliation ledger table + migration",         meta: "+96 −12 · 3 files" },
      { tag: "IMPL", text: "Applied patch: dedupe partial fills by venue order id", meta: "+142 −38 · 4 files" },
      { tag: "IMPL", text: "Extracted venue policy from router hot path",           meta: "+58 −41 · 2 files" }
    ],
    "review" => [
      { tag: "REVIEW", text: "Critic flagged missing idempotency key on retry path", meta: "2 comments" },
      { tag: "REVIEW", text: "Review comments resolved, spec check green",           meta: "0 open" }
    ],
    "testing" => [
      { tag: "TEST", text: "Property test found off-by-one on partial fills", meta: "1 failing · retrying" },
      { tag: "TEST", text: "Suite green after retry — 47 passed, 0 failed",   meta: "2m 14s" }
    ],
    "deployment" => [
      { tag: "DEPLOY", text: "Staged rollout 10% → metrics nominal for 12m", meta: "p99 41ms" },
      { tag: "DEPLOY", text: "Canary holding — no error budget burn",        meta: "20m window" }
    ]
  }.freeze

  TRANSITION_TEXT = {
    "planning"       => "Investigation complete — root cause confirmed, entering planning",
    "implementation" => "Plan accepted — subtasks filed, implementation started",
    "review"         => "Implementation done — patch handed to Critic for review",
    "testing"        => "Review passed — running the full test suite",
    "deployment"     => "Tests green — beginning staged rollout"
  }.freeze

  COMMIT_MESSAGES = [
    "reconcile: dedupe partial fills by venue order id",
    "core: extract venue policy from router",
    "jobs: hot-reload strategy registry without restart",
    "api: tighten schema validation on risk endpoints",
    "spec: update scenarios for changed capability",
    "core: property-test partial fill ordering"
  ].freeze

  ARCHITECT_REPLIES = [
    { body: "Noted — folding that constraint into the plan. I'll update the affected subtasks and re-run the dependency check before Builder-1 picks anything up.",
      attach: "plan-alg-215.md" },
    { body: "Good catch. I've written that into the spec as an explicit scenario rather than leaving it in the plan only, so the Critic will enforce it at review time.",
      attach: "openspec/exec/order-router.md · R-4" },
    { body: "Understood. That changes the venue scoring weights — I'll source fill quality from the last 30d of fills and keep latency as a tiebreaker only.",
      attach: nil }
  ].freeze

  BACKLOG_TEMPLATES = [
    { title: "Venue outage failover drill automation", repo: "algo-jobs", est: "~1h 20m", risky: false },
    { title: "Latency budget alerts per venue", repo: "algo-jobs", est: "~50m", risky: false },
    { title: "Order intent replay tooling for incident review", repo: "algo-core", est: "~2h", risky: false },
    { title: "Fee schedule sync from venue APIs", repo: "algo-api", est: "~1h", risky: false },
    { title: "Shadow-mode testing for router policy changes", repo: "algo-core", est: "~2h 30m", risky: true },
    { title: "Backtest result diffing between code versions", repo: "algo-api", est: "~1h 40m", risky: false }
  ].freeze

  module_function

  def note_for(phase)
    PHASE_NOTES[phase]
  end

  def activity_for(ticket, seq)
    pool = ACTIVITY.fetch(ticket.state, ACTIVITY["implementation"])
    pool[seq % pool.size]
  end

  def transition_text(ticket, _from, to)
    "#{TRANSITION_TEXT.fetch(to, "Entering #{to}")} (#{ticket.code})"
  end

  def start_text(ticket)
    "Picked up #{ticket.code} — #{ticket.title}"
  end

  def doing_text(ticket)
    "#{ticket.code} #{ticket.state}: #{ticket.title.downcase.truncate(48)}"
  end

  def commit_message(seq)
    COMMIT_MESSAGES[seq % COMMIT_MESSAGES.size]
  end

  def gate_reason(ticket, next_state, mode)
    if mode == "every"
      "#{ticket.code} finished #{ticket.state} — approve to enter #{next_state}."
    elsif ticket.code == "ALG-198"
      "#{ticket.code} touches the kill switch (risky) — approve to enter #{next_state}."
    elsif ticket.risky?
      "#{ticket.code} is marked risky — approve to enter #{next_state}."
    else
      "#{ticket.code} is ready to deploy — approve the rollout."
    end
  end

  def architect_reply(message)
    ARCHITECT_REPLIES[message.id % ARCHITECT_REPLIES.size]
  end

  def fabricate_backlog_ticket
    number = Ticket.pluck(:code).filter_map { |c| c[/\d+/]&.to_i }.max.to_i + 1
    template = BACKLOG_TEMPLATES[number % BACKLOG_TEMPLATES.size]
    Ticket.create!(code: "ALG-#{number}", title: template[:title], repo: template[:repo],
                   est_label: template[:est], risky: template[:risky], state: :backlog)
  end
end
