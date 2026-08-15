# Demo workspace seed — the "algo" trading platform from the design prototype.
# Idempotent: skips when data is already present.

# Guard on Setting, not tickets: once the app has booted (and especially once
# live mode purged the demo board), a restart must never re-seed demo data.
if Setting.any? || Ticket.any?
  puts "Application state already present — skipping seeds."
else
  now = Time.current

  ActiveRecord::Base.transaction do
    setting = Setting.instance
    setting.update!(autonomy: "auto", running: true, spend_today: 41.28, spend_cap: 80,
                    setup_complete: true,
                    setup: { "repo0" => "true", "repo1" => "true", "repo2" => "true", "repo3" => "false",
                             "auth" => "0", "fw" => "0" })

    # ── agents ────────────────────────────────────────────────
    agents = [
      { name: "Scout",     abbr: "SC", role: "investigation",   llm_model: "sonnet", status: "idle",
        doing: "Last: reproduced slippage delta on ALG-218 replay window",
        tools: ["ripgrep", "git log", "test runner", "trace replay"], cost_today: 6.10 },
      { name: "Architect", abbr: "AR", role: "planning · spec", llm_model: "opus", status: "running",
        doing: "Splitting ALG-215 router into venue adapter + policy layer",
        tools: ["openspec", "dep graph", "ticket writer"], cost_today: 13.40 },
      { name: "Builder-1", abbr: "B1", role: "implementation",  llm_model: "sonnet", status: "running",
        doing: "ALG-212 hot-reload: watcher + strategy registry swap",
        tools: ["editor", "shell", "patch"], cost_today: 8.05 },
      { name: "Builder-2", abbr: "B2", role: "implementation",  llm_model: "sonnet", status: "running",
        doing: "ALG-207 reconciliation ledger + migration",
        tools: ["editor", "shell", "patch"], cost_today: 7.62 },
      { name: "Critic",    abbr: "CR", role: "review",          llm_model: "opus", status: "waiting",
        doing: "Blocked on ALG-203 — awaiting your call on idempotency keys",
        tools: ["diff reader", "spec check"], cost_today: 3.90 },
      { name: "Tester",    abbr: "TS", role: "testing",         llm_model: "sonnet", status: "running",
        doing: "Property suite on partial fills, seed 4471",
        tools: ["pytest", "hypothesis", "coverage"], cost_today: 1.81 },
      { name: "Shipper",   abbr: "SH", role: "deployment",      llm_model: "haiku", status: "idle",
        doing: "Last: v0.41.2 canary held 20m, promoted",
        tools: ["git tag", "changelog", "deploy"], cost_today: 0.40 }
    ].each_with_index.map { |a, i| Agent.create!(a.merge(position: i)) }
    by_name = agents.index_by(&:name)

    # ── board tickets (mirrors the prototype board) ───────────
    diff_alg207 = [
      { "line" => "--- a/algo-core/exec/reconcile.py", "bg" => "transparent", "fg" => "var(--tx3)" },
      { "line" => "+++ b/algo-core/exec/reconcile.py", "bg" => "transparent", "fg" => "var(--tx3)" },
      { "line" => "@@ -84,12 +84,21 @@ def apply_fill(state, fill):", "bg" => "var(--sunken)", "fg" => "var(--info)" },
      { "line" => "-    key = fill.order_id", "bg" => "var(--err-soft)", "fg" => "var(--err)" },
      { "line" => "-    if key in state.seen:", "bg" => "var(--err-soft)", "fg" => "var(--err)" },
      { "line" => "-        return state", "bg" => "var(--err-soft)", "fg" => "var(--err)" },
      { "line" => "+    key = (fill.venue, fill.order_id, fill.seq)", "bg" => "var(--ok-soft)", "fg" => "var(--ok)" },
      { "line" => "+    if key in state.seen:", "bg" => "var(--ok-soft)", "fg" => "var(--ok)" },
      { "line" => "+        return state          # exactly-once per venue seq", "bg" => "var(--ok-soft)", "fg" => "var(--ok)" },
      { "line" => "+    if fill.qty < intent.qty:", "bg" => "var(--ok-soft)", "fg" => "var(--ok)" },
      { "line" => "+        state = _record_partial(state, intent, fill)", "bg" => "var(--ok-soft)", "fg" => "var(--ok)" },
      { "line" => "     state.seen.add(key)", "bg" => "transparent", "fg" => "var(--tx2)" }
    ]

    tickets = [
      { code: "ALG-236", title: "Deprecate v1 signal webhook", state: :backlog, repo: "algo-api", est_label: "~1h" },
      { code: "ALG-231", title: "Backfill historical OHLC gaps for 2019–2021", state: :backlog, repo: "algo-jobs", est_label: "~3h" },
      { code: "ALG-229", title: "Position sizing config schema + validation", state: :ready, repo: "algo-core", est_label: "~2h" },
      { code: "ALG-224", title: "Rate-limit /v2/backtest per API key", state: :ready, repo: "algo-api", est_label: "~1h 20m" },
      { code: "ALG-218", title: "Slippage model mismatch between paper and live fills", state: :investigation,
        repo: "algo-core", est_label: "~2h", risky: true, agent: by_name["Scout"] },
      { code: "ALG-215", title: "Multi-venue order router", state: :planning,
        repo: "algo-core · algo-api", est_label: "~6h", risky: true, agent: by_name["Architect"] },
      { code: "ALG-207", title: "Idempotent fill reconciliation", state: :implementation,
        repo: "algo-core", est_label: "~2h 40m", agent: by_name["Builder-2"],
        cost: 2.10, tokens_label: "184k tok", diff: diff_alg207,
        dep_codes: ["ALG-229", "ALG-218"],
        artifacts: ["plan-alg-207.md", "openspec/exec/fill-reconciliation.md", "branch pipe/alg-207", "test report 14:19"] },
      { code: "ALG-212", title: "Strategy hot-reload without process restart", state: :implementation,
        repo: "algo-jobs", est_label: "~3h", agent: by_name["Builder-1"] },
      { code: "ALG-203", title: "Portfolio risk snapshot endpoint", state: :review,
        repo: "algo-api", est_label: "~1h 10m", agent: by_name["Critic"] },
      { code: "ALG-198", title: "Kill-switch on 8% intraday drawdown", state: :testing,
        repo: "algo-core", est_label: "~2h", risky: true, agent: by_name["Tester"] },
      { code: "ALG-191", title: "Metrics exporter v2 (venue latency histograms)", state: :deployment,
        repo: "algo-jobs", est_label: "~40m", agent: by_name["Shipper"] }
    ].map { |t| Ticket.create!(t) }
    by_code = tickets.index_by(&:code)

    # Phase history for in-flight tickets (drives drawer phases + durations).
    phase_secs = { "investigation" => 18 * 60, "planning" => 24 * 60, "implementation" => 66 * 60,
                   "review" => 9 * 60, "testing" => 14 * 60, "deployment" => 6 * 60 }
    tickets.select { |t| t.phase_index }.each do |t|
      cursor = now - 4.hours + rand(30).minutes
      t.update!(started_at: cursor)
      Ticket::PHASES.first(t.phase_index).each do |phase|
        secs = phase_secs[phase]
        t.phase_runs.create!(phase: phase, status: "done", note: DemoScript.note_for(phase),
                             started_at: cursor, finished_at: cursor + secs, duration_s: secs)
        cursor += secs
      end
      t.phase_runs.create!(phase: t.state, status: "running",
                           note: DemoScript.note_for(t.state), started_at: cursor)
    end

    # Shipped history — feeds the cycle-time panel with real PhaseRun data.
    hist = { "investigation" => 42 * 60, "planning" => 27 * 60, "implementation" => 104 * 60,
             "review" => 62 * 60, "testing" => 51 * 60, "deployment" => 14 * 60 }
    [
      { code: "ALG-190", title: "Vendor failover for OHLC ingest", repo: "algo-jobs" },
      { code: "ALG-186", title: "Backtest snapshot pinning on retry", repo: "algo-api" },
      { code: "ALG-183", title: "Risk snapshot schema v1", repo: "algo-api" },
      { code: "ALG-179", title: "Order intent audit trail", repo: "algo-core" }
    ].each_with_index do |t, i|
      jitter = 1.0 + (i - 1.5) * 0.12
      start = now - (2 + i).days
      ticket = Ticket.create!(t.merge(state: :done, est_label: "~2h", started_at: start))
      cursor = start
      Ticket::PHASES.each do |phase|
        secs = (hist[phase] * jitter).round
        ticket.phase_runs.create!(phase: phase, status: "done", note: DemoScript.note_for(phase),
                                  started_at: cursor, finished_at: cursor + secs, duration_s: secs)
        cursor += secs
      end
      ticket.update!(finished_at: cursor)
    end

    # ── needs-you questions (block their tickets) ─────────────
    Question.create!(
      ticket_code: "ALG-203", phase: "review", asked_at: now - 22.minutes,
      body: "Retry path has no idempotency key. Add one to the request envelope (breaking for v1 clients) or dedupe server-side by payload hash?",
      options: ["Envelope key", "Server-side hash", "Discuss"]
    )
    Question.create!(
      ticket_code: "ALG-218", phase: "investigation", asked_at: now - 6.minutes,
      body: "Paper and live disagree on fee-then-slippage ordering. Which is the source of truth?",
      options: ["Live is truth", "Spec is truth", "Open ticket"]
    )

    # ── event stream (recent history) ─────────────────────────
    [
      { at: now - 1.minute, tag: "IMPL", text: "Applied patch: reconcile partial fills by venue order id",
        code: "ALG-207", agent: "Builder-2", meta: "+142 −38 · 4 files" },
      { at: now - 3.minutes, tag: "TEST", tone: "var(--ok)", text: "Suite green after retry — 47 passed, 0 failed",
        code: "ALG-212", agent: "Tester", meta: "2m 14s" },
      { at: now - 6.minutes, tag: "REVIEW", text: "Requested changes: extract venue policy from router",
        code: "ALG-203", agent: "Critic", meta: "2 comments" },
      { at: now - 13.minutes, tag: "PLAN", text: "Plan accepted — 5 tickets filed with dependency order",
        code: "ALG-215", agent: "Architect", meta: "est 6h" },
      { at: now - 19.minutes, tag: "INVEST", text: "Root cause: fee model applied before slippage, not after",
        code: "ALG-218", agent: "Scout", meta: "confidence 0.81" },
      { at: now - 28.minutes, tag: "DEPLOY", text: "v0.41.2 shipped to prod — canary held 20m",
        code: "ALG-191", agent: "Shipper", meta: "no regressions" },
      { at: now - 41.minutes, tag: "SPEC", text: "Parsed 11 openspec capabilities, 68 requirements",
        code: "—", agent: "Scout", meta: "index 2.1k files" }
    ].each do |e|
      Event.create!(happened_at: e[:at], phase_tag: e[:tag],
                    tone: e[:tone] || Event::DEFAULT_TONES[e[:tag]],
                    text: e[:text], ticket_code: e[:code], agent_name: e[:agent], meta: e[:meta])
    end

    # ── commits / releases / CI ───────────────────────────────
    [
      { sha: "a41f9c2", message: "reconcile: dedupe partial fills by venue order id", author: "Builder-2", at: now - 2.minutes },
      { sha: "7d0e114", message: "jobs: hot-reload strategy registry without restart", author: "Builder-1", at: now - 19.minutes },
      { sha: "c93ab77", message: "api: risk snapshot endpoint + schema", author: "Builder-1", at: now - 1.hour },
      { sha: "2f5d803", message: "spec: kill-switch per-venue scoping (R-3)", author: "Architect", at: now - 2.hours },
      { sha: "e18c6aa", message: "obs: venue latency histograms", author: "Shipper", at: now - 4.hours },
      { sha: "b74d219", message: "core: extract fee model from slippage calc", author: "Scout", at: now - 5.hours }
    ].each { |c| CommitRecord.create!(sha: c[:sha], message: c[:message], author: c[:author], committed_at: c[:at]) }

    Release.create!(version: "v0.41.2", kind: "shipped", position: 0, released_at: now - 28.minutes,
                    date_label: "today #{(now - 28.minutes).strftime('%H:%M')}",
                    lines: ["Venue latency histograms in metrics exporter", "Fix: backtest snapshot pinning on retry"])
    Release.create!(version: "v0.41.1", kind: "shipped", position: 1, released_at: now - 1.day,
                    date_label: "yesterday",
                    lines: ["Risk snapshot endpoint (GET /v2/risk/snapshot)"])
    Release.create!(version: "v0.42.0", kind: "staged", position: 2, date_label: "pending",
                    lines: ["Idempotent fill reconciliation", "Kill-switch per-venue scoping"])

    [
      { name: "algo-core · unit", pct: 99 }, { name: "algo-core · property", pct: 94 },
      { name: "algo-api · integration", pct: 97 }, { name: "algo-web · e2e", pct: 88 }
    ].each_with_index { |c, i| CiSuite.create!(c.merge(position: i)) }

    # ── spend bars: last 14 hours, scaled to today's total ────
    heights = [34, 52, 28, 61, 44, 73, 39, 58, 47, 66, 31, 55, 70, 52]
    scale = 41.28 / heights.sum
    heights.each_with_index do |h, i|
      SpendSample.create!(bucket: (now - (13 - i).hours).beginning_of_hour, amount: (h * scale).round(2))
    end

    # ── chat thread (Architect on ALG-215) ────────────────────
    [
      { s: "architect", at: now - 15.minutes, attach: "plan-alg-215.md",
        b: "Plan for ALG-215 is two layers: a thin venue adapter per exchange, and one policy layer that ranks venues by cost + latency. That keeps the retry logic in one place." },
      { s: "you", at: now - 14.minutes,
        b: "Don't rank on latency alone — Binance is fast but fills worse on size. Weight fill quality above latency." },
      { s: "architect", at: now - 13.minutes,
        b: "Updated: score = 0.5·fill quality + 0.3·fee + 0.2·latency, sourced from the last 30d of fills. Fill quality needs a definition — using slippage vs arrival price unless you say otherwise." },
      { s: "you", at: now - 12.minutes,
        b: "Arrival price is right. Also write it into the spec, not just the plan." },
      { s: "architect", at: now - 12.minutes, attach: "openspec/exec/order-router.md · R-4",
        b: "Filed 5 tickets in dependency order and added exec/order-router R-4 \"venue scoring\". Builder-1 picks up the adapter as soon as the schema ticket lands." }
    ].each do |m|
      ChatMessage.create!(room: "ALG-215", sender: m[:s], body: m[:b],
                          attach_label: m[:attach], sent_at: m[:at])
    end

    # ── openspec capabilities ─────────────────────────────────
    specs_data = [
      { slug: "risk/kill-switch", title: "Kill switch", meta_label: "6 reqs · linked ALG-198",
        purpose: "Halt new order submission when intraday drawdown breaches a configured threshold, and require explicit human re-arm.",
        tags: ["owner: risk", "linked: ALG-198", "last agent edit 2h ago"],
        reqs: [
          { rid: "R-1", name: "Threshold breach halts submission", status: "implemented",
            body: "When realised + unrealised intraday P&L falls below the configured drawdown threshold, the system MUST reject new order intents while allowing risk-reducing exits.",
            impl_ref: "algo-core/risk/killswitch.py", tests_label: "12 tests",
            scenarios: [
              { name: "Scenario · breach",
                body: "GIVEN equity is down 8.1% intraday\nWHEN a new long intent is submitted\nTHEN it is rejected with RISK_HALT and a pipeline alert is raised" },
              { name: "Scenario · risk-reducing",
                body: "GIVEN the halt is active and a position is open\nWHEN a closing order is submitted\nTHEN it is accepted and logged as risk-reducing" }
            ] },
          { rid: "R-2", name: "Re-arm requires a human", status: "implemented",
            body: "The halt MUST NOT clear automatically. Re-arming requires an operator action recorded with actor, timestamp and reason.",
            impl_ref: "algo-core/risk/rearm.py", tests_label: "6 tests",
            scenarios: [
              { name: "Scenario · auto-clear forbidden",
                body: "GIVEN a halt was raised 24h ago\nWHEN a new trading day starts\nTHEN the halt remains active until re-armed" }
            ] },
          { rid: "R-3", name: "Per-venue scoping", status: "in review",
            body: "A breach attributable to a single venue SHOULD halt that venue only, unless portfolio-level drawdown is also breached.",
            impl_ref: "pending ALG-198", tests_label: "3 pending",
            scenarios: [
              { name: "Scenario · single venue",
                body: "GIVEN venue B accounts for the entire breach\nWHEN the halt is evaluated\nTHEN only venue B is halted and the reason names it" }
            ] }
        ] },
      { slug: "risk/position-sizing", title: "Position sizing", meta_label: "4 reqs · draft",
        purpose: "Derive order size from account equity, volatility target and per-venue exposure caps.",
        tags: ["owner: risk", "draft"],
        reqs: [
          { rid: "R-1", name: "Volatility-scaled sizing", status: "implemented",
            body: "Order size MUST scale inversely with the instrument's trailing 30d volatility so portfolio risk stays near the configured target.",
            impl_ref: "algo-core/risk/sizing.py", tests_label: "8 tests",
            scenarios: [
              { name: "Scenario · vol spike",
                body: "GIVEN trailing volatility doubles overnight\nWHEN the next intent is sized\nTHEN its notional is roughly halved" }
            ] },
          { rid: "R-4", name: "Venue exposure axis", status: "pending",
            body: "Sizing SHOULD accept a per-venue exposure cap input; the venue axis is reserved for the upcoming exposure-cap capability.",
            impl_ref: "reserved", tests_label: "—", scenarios: [] }
        ] },
      { slug: "exec/order-router", title: "Order router", meta_label: "9 reqs · in planning",
        purpose: "Route orders across venues by cost, latency and available liquidity, with deterministic fallback ordering.",
        tags: ["owner: exec", "linked: ALG-215", "in planning"],
        reqs: [
          { rid: "R-1", name: "Deterministic fallback order", status: "implemented",
            body: "When the preferred venue rejects or times out, the router MUST walk a deterministic, configured fallback list — never a random or load-dependent order.",
            impl_ref: "algo-core/exec/router.py", tests_label: "14 tests",
            scenarios: [
              { name: "Scenario · timeout",
                body: "GIVEN venue A times out after 250ms\nWHEN the intent is re-routed\nTHEN venue B receives it with the original idempotency key" }
            ] },
          { rid: "R-4", name: "Venue scoring", status: "in review",
            body: "Venue rank SHOULD be scored as 0.5·fill quality + 0.3·fee + 0.2·latency, computed from the last 30 days of fills; fill quality is slippage vs arrival price.",
            impl_ref: "pending ALG-215", tests_label: "draft",
            scenarios: [
              { name: "Scenario · quality beats speed",
                body: "GIVEN venue A is faster but fills 40bps worse on size\nWHEN venues are ranked for a large intent\nTHEN the better-filling venue ranks first" }
            ] }
        ] },
      { slug: "exec/fill-reconciliation", title: "Fill reconciliation", meta_label: "7 reqs · implementing",
        purpose: "Reconcile venue fills against internal intents exactly once, tolerating retries, partials and out-of-order events.",
        tags: ["owner: exec", "linked: ALG-207", "implementing"],
        reqs: [
          { rid: "R-1", name: "Exactly-once application", status: "in review",
            body: "A fill MUST be applied exactly once, keyed by (venue, order_id, seq), regardless of gateway retries or replay.",
            impl_ref: "algo-core/exec/reconcile.py", tests_label: "9 tests",
            scenarios: [
              { name: "Scenario · duplicate delivery",
                body: "GIVEN the same fill arrives twice\nWHEN reconciliation runs\nTHEN position and P&L change only once" }
            ] },
          { rid: "R-2", name: "Partial fills accumulate", status: "in review",
            body: "Partial fills MUST accumulate against the intent quantity and close the intent when filled or expired.",
            impl_ref: "algo-core/exec/reconcile.py", tests_label: "property suite",
            scenarios: [] }
        ] },
      { slug: "data/ohlc-backfill", title: "OHLC backfill", meta_label: "5 reqs · stable",
        purpose: "Detect and repair candle gaps from historical vendors without corrupting derived features.",
        tags: ["owner: data", "stable"],
        reqs: [
          { rid: "R-1", name: "Gap detection", status: "implemented",
            body: "The backfill job MUST detect missing candles per instrument and venue calendar, distinguishing halts from vendor gaps.",
            impl_ref: "algo-jobs/backfill/gaps.py", tests_label: "11 tests",
            scenarios: [
              { name: "Scenario · exchange halt",
                body: "GIVEN a venue-wide halt of 40 minutes\nWHEN gap detection runs\nTHEN those candles are marked HALT, not MISSING" }
            ] },
          { rid: "R-2", name: "Feature invalidation", status: "implemented",
            body: "Repairing a candle MUST invalidate and rebuild every derived feature window that consumed it.",
            impl_ref: "algo-jobs/backfill/repair.py", tests_label: "7 tests", scenarios: [] }
        ] },
      { slug: "api/backtest-v2", title: "Backtest API v2", meta_label: "8 reqs · stable",
        purpose: "Run reproducible backtests with pinned data snapshots and per-key fair-use limits.",
        tags: ["owner: api", "stable"],
        reqs: [
          { rid: "R-1", name: "Snapshot pinning", status: "implemented",
            body: "A backtest MUST pin the exact data snapshot at submission; retries and re-runs MUST reuse it byte-for-byte.",
            impl_ref: "algo-api/backtest/snapshots.py", tests_label: "13 tests",
            scenarios: [
              { name: "Scenario · retry",
                body: "GIVEN a backtest worker dies mid-run\nWHEN the run is retried\nTHEN results are identical to an uninterrupted run" }
            ] },
          { rid: "R-3", name: "Per-key fair use", status: "pending",
            body: "Each API key SHOULD be rate-limited on /v2/backtest by rolling compute budget, not request count.",
            impl_ref: "pending ALG-224", tests_label: "—", scenarios: [] }
        ] },
      { slug: "obs/metrics-exporter", title: "Metrics exporter", meta_label: "6 reqs · shipped",
        purpose: "Expose venue latency, fill quality and risk state as Prometheus metrics.",
        tags: ["owner: obs", "linked: ALG-191", "shipped"],
        reqs: [
          { rid: "R-1", name: "Venue latency histograms", status: "implemented",
            body: "The exporter MUST publish per-venue order-ack latency histograms with p50/p99 quantiles over 5m windows.",
            impl_ref: "algo-jobs/obs/exporter.py", tests_label: "6 tests",
            scenarios: [
              { name: "Scenario · scrape",
                body: "GIVEN Prometheus scrapes /metrics\nWHEN venue B degrades\nTHEN venue_ack_latency p99 for B reflects it within one window" }
            ] },
          { rid: "R-2", name: "Risk state gauge", status: "implemented",
            body: "The current kill-switch state MUST be exported as a gauge with the halting venue as a label.",
            impl_ref: "algo-jobs/obs/exporter.py", tests_label: "3 tests", scenarios: [] }
        ] }
    ]

    specs_data.each_with_index do |s, i|
      spec = Capability.create!(slug: s[:slug], file: "openspec/#{s[:slug]}.md", title: s[:title],
                          purpose: s[:purpose], meta_label: s[:meta_label], tags: s[:tags], position: i)
      s[:reqs].each_with_index do |r, j|
        req = spec.spec_requirements.create!(
          rid: r[:rid], name: r[:name], status: r[:status], body: r[:body],
          impl_ref: r[:impl_ref], tests_label: r[:tests_label], position: j
        )
        r[:scenarios].each_with_index do |sc, k|
          req.spec_scenarios.create!(name: sc[:name], body: sc[:body], position: k)
        end
      end
    end
  end

  puts "Seeded: #{Ticket.count} tickets, #{Agent.count} agents, #{Capability.count} specs, #{Event.count} events."
end
