# Canned output of the RFC investigation/planning flow. In a real deployment
# this is the seam where an actual investigating agent (Scout/Architect) would
# produce trace, questions and a ticket plan for the submitted request.
module RfcScript
  TRACE = [
    { "mark" => "✓", "tone" => "var(--ok)",   "text" => "read 41 files across algo-core, algo-api — exposure logic lives in 3 places" },
    { "mark" => "✓", "tone" => "var(--ok)",   "text" => "found existing per-symbol cap in risk/limits.py (2023, unspecced)" },
    { "mark" => "✓", "tone" => "var(--ok)",   "text" => "openspec: risk/position-sizing R-4 already reserves the venue axis" },
    { "mark" => "✓", "tone" => "var(--ok)",   "text" => "git log: 2 reverted attempts at venue caps (Jan, Apr) — both raced the router" },
    { "mark" => "!", "tone" => "var(--warn)", "text" => "no venue identifier on OrderIntent — needs a schema change" },
    { "mark" => "!", "tone" => "var(--warn)", "text" => "halt semantics ambiguous: halt venue only, or whole book?" }
  ].freeze

  QUESTIONS = [
    { "key" => "q1", "q" => "On breach, halt only the offending venue or the whole book?",
      "why" => "changes blast radius and rollback story",
      "opts" => ["Venue only", "Whole book", "Configurable"] },
    { "key" => "q2", "q" => "Is the cap notional, or a share of account equity?",
      "why" => "notional is simpler; equity share self-adjusts",
      "opts" => ["Notional", "Equity share"] },
    { "key" => "q3", "q" => "Reuse the unspecced cap in risk/limits.py, or replace it?",
      "why" => "reuse is faster; replacing removes a 2023 landmine",
      "opts" => ["Reuse", "Replace", "Agent decides"] }
  ].freeze

  PROPOSALS = [
    { "step" => "1", "id" => "ALG-241", "title" => "Add venue field to OrderIntent + migration",
      "repo" => "algo-core", "dep" => "no deps", "dep_codes" => [], "est" => "40m",
      "tag" => "schema", "tone" => "var(--info)" },
    { "step" => "2", "id" => "ALG-242", "title" => "Per-venue exposure accumulator in risk engine",
      "repo" => "algo-core", "dep" => "needs 241", "dep_codes" => ["ALG-241"], "est" => "1h 30m",
      "tag" => "core", "tone" => "var(--accent)" },
    { "step" => "3", "id" => "ALG-243", "title" => "Halt venue on breach, keep risk-reducing exits",
      "repo" => "algo-core", "dep" => "needs 242", "dep_codes" => ["ALG-242"], "est" => "1h 10m",
      "tag" => "risky", "tone" => "var(--err)" },
    { "step" => "4", "id" => "ALG-244", "title" => "Expose caps + breach state on /v2/risk/snapshot",
      "repo" => "algo-api", "dep" => "needs 242", "dep_codes" => ["ALG-242"], "est" => "50m",
      "tag" => "api", "tone" => "var(--info)" },
    { "step" => "5", "id" => "ALG-245", "title" => "Property tests: concurrent fills across venues",
      "repo" => "algo-core", "dep" => "needs 243", "dep_codes" => ["ALG-243"], "est" => "1h",
      "tag" => "tests", "tone" => "var(--warn)" }
  ].freeze
end
