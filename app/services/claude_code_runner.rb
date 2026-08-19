require "open3"
require "json"
require "shellwords"

# Executes one pipeline phase as a real headless Claude Code run inside the
# ticket's workspace repository (process handling lives in HeadlessAgent).
# Streams the agent's messages into the live event feed, accounts real cost,
# captures commits/diff, then hands the ticket back to PipelineEngine for the
# (possibly gated) transition.
class ClaudeCodeRunner
  # A pipeline that cannot run a linter or a test suite cannot review its own
  # work. acceptEdits denies every Bash command, which failed the testing
  # phase outright and burned turns on retries until runs hit their limit.
  # The boundary that matters is the mounted workspace and the pipe/* branch,
  # not the permission prompt. Override with CLAUDE_FLAGS to tighten it.
  DEFAULT_FLAGS = "--permission-mode bypassPermissions".freeze
  DEFAULT_BIN = "claude".freeze

  class << self
    def bin
      ENV.fetch("CLAUDE_BIN", DEFAULT_BIN)
    end

    def bin_path
      return bin if bin.include?("/") && File.executable?(bin)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
         .map { |dir| File.join(dir, bin) }
         .find { |candidate| File.executable?(candidate) }
    end

    def available?(setting = Setting.instance)
      return false unless bin_path
      # A custom binary (stub/wrapper) manages its own auth.
      return true if bin != DEFAULT_BIN

      setting.subscription_auth? ? subscription_credentials? : api_key?
    end

    def api_key?
      ENV["ANTHROPIC_API_KEY"].present?
    end

    def subscription_credentials?
      ENV["CLAUDE_CODE_OAUTH_TOKEN"].present? || File.exist?(credentials_path)
    end

    def credentials_path
      dir = ENV["CLAUDE_CONFIG_DIR"].presence || "~/.claude"
      File.expand_path(File.join(dir, ".credentials.json"))
    end

    # { ok:, label: } for the setup wizard's auth step.
    def auth_status(setting = Setting.instance)
      if setting.subscription_auth?
        if ENV["CLAUDE_CODE_OAUTH_TOKEN"].present?
          { ok: true, label: "✓ CLAUDE_CODE_OAUTH_TOKEN detected" }
        elsif File.exist?(credentials_path)
          { ok: true, label: "✓ subscription login found (#{credentials_path})" }
        else
          { ok: false, label: "no subscription credentials — mount ~/.claude or set CLAUDE_CODE_OAUTH_TOKEN" }
        end
      elsif api_key?
        { ok: true, label: "✓ ANTHROPIC_API_KEY detected (…#{ENV['ANTHROPIC_API_KEY'].to_s.last(4)})" }
      else
        { ok: false, label: "no ANTHROPIC_API_KEY in environment" }
      end
    end
  end

  attr_reader :ticket, :run, :phase

  def initialize(ticket, run)
    @ticket = ticket
    @run = run
    @phase = run.phase
  end

  def execute
    repo = Workspace.repo_path(ticket.repo)
    return fail_run("repository #{ticket.repo.inspect} not found in workspace") unless repo

    prepare_branch(repo)
    PhaseOutput.clear(run)
    plan = PhasePrompts.execution(ticket, phase, repo, Setting.instance, run)
    harness_run = plan[:chdir] != repo
    Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent,
                  meta: harness_run ? "harness run" : "live run",
                  text: "Started #{phase} run (#{harness_run ? plan[:prompt].lines.first.to_s.strip.truncate(40) : 'claude code'})")

    result = HeadlessAgent.call(prompt: plan[:prompt], chdir: plan[:chdir],
                                extra_args: plan[:extra_args], env: child_env,
                                model: ticket.agent&.effective_model) do |data|
      case data["type"]
      when "system"
        run.update!(session_id: data["session_id"]) if data["session_id"]
      when "assistant"
        narrate(data)
      end
    end

    run.update!(log: result.log.to_s.last(50_000), exit_status: result.exit_status,
                cost: result.cost.to_f)

    # A run that failed still burned tokens. Charge it before branching, or
    # the ledger reports $0 for money that was very much spent.
    accrue_cost(result.raw) if result.raw

    if result.ok
      capture_outputs(repo)
      rerouted = handle_structured_output(result) == :rerouted
      Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent,
                    meta: run_meta(result.raw),
                    text: "#{phase.capitalize} run finished — #{summary(result.raw)}")
      # A review that sent the ticket back has already moved it and started the
      # rework run; advancing it again would skip implementation entirely.
      PipelineEngine.phase_finished!(ticket) unless rerouted
    else
      salvage(repo, result)
      fail_run(result.error.to_s)
    end
  rescue StandardError => e
    fail_run("#{e.class}: #{e.message}")
  end

  private

  # Only the credential matching the chosen auth mode reaches the CLI, so
  # subscription runs never silently bill the API key and vice versa.
  def child_env
    if Setting.instance.subscription_auth?
      { "ANTHROPIC_API_KEY" => nil }
    else
      { "CLAUDE_CODE_OAUTH_TOKEN" => nil }
    end
  end

  def tag
    PipelineText::TAGS.fetch(phase, "IMPL")
  end

  # Implementation happens on a dedicated work branch; later phases keep
  # operating on it because it stays checked out.
  # `checkout -B` resets an existing branch to whatever HEAD happens to be —
  # after a merge conflict leaves HEAD on the base branch, a retry would
  # silently throw away every implementation commit. Create it once, then only
  # ever switch to it.
  def prepare_branch(repo)
    return unless %w[implementation review testing deployment].include?(phase)

    branch = ticket.branch_name
    exists = system("git", "-C", repo, "rev-parse", "--verify", branch,
                    out: File::NULL, err: File::NULL)
    unless exists
      # Cut from the base branch, never from wherever HEAD happens to sit. The
      # previous ticket leaves the repo on its own pipe/* branch, so branching
      # from HEAD quietly gave every ticket the last one's commits.
      start = GitRepo.base_branch(repo)
      args = ["checkout", "-b", branch, start].compact
      return unless system("git", "-C", repo, *args, out: File::NULL, err: File::NULL)

      ticket.update!(artifacts: ticket.artifacts | ["branch #{branch}"])
      return
    end

    system("git", "-C", repo, "checkout", branch, out: File::NULL, err: File::NULL)
  end

  def narrate(data)
    Array(data.dig("message", "content")).each do |part|
      case part["type"]
      when "text"
        snippet = part["text"].to_s.strip.gsub(/\s+/, " ").truncate(140)
        next if snippet.blank?

        Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent, meta: "claude", text: snippet)
        run.update!(note: snippet.truncate(80))
        ticket.agent&.update!(status: "running", doing: "#{ticket.code}: #{snippet.truncate(60)}")
      when "tool_use"
        Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent, meta: "tool",
                      text: "→ #{part['name']} #{tool_brief(part['input'])}".strip)
      end
    end
  end

  def tool_brief(input)
    return "" unless input.is_a?(Hash)

    (input["file_path"] || input["command"] || input["pattern"] || input["path"]).to_s.truncate(80)
  end

  def run_meta(result)
    secs = (result["duration_ms"].to_i / 1000.0).round
    "#{secs}s · $#{format('%.2f', result['total_cost_usd'].to_f)}"
  end

  def summary(result)
    result["result"].to_s.strip.gsub(/\s+/, " ").truncate(120).presence || "no summary"
  end

  def accrue_cost(result)
    cost = result["total_cost_usd"].to_f.round(4)
    return unless cost.positive?

    SpendEntry.record!(cost, source: "phase", phase: phase, ticket: ticket,
                       agent: ticket.agent, llm_model: ticket.agent&.effective_model || HeadlessAgent.model_name)

    usage = result["usage"] || {}
    tokens = usage.values_at("input_tokens", "output_tokens", "cache_read_input_tokens").compact.sum
    ticket.update!(tokens_label: "#{(tokens / 1000.0).ceil}k tok") if tokens.positive?
  end

  def capture_outputs(repo)
    capture_commits(repo)
    capture_diff(repo) if %w[implementation review testing].include?(phase)
    capture_plan_artifact if phase == "planning"
  end

  def capture_commits(repo)
    out, ok = git(repo, "log", "-5", "--pretty=%h%x09%s")
    return unless ok

    out.lines.reverse_each do |line|
      sha, message = line.chomp.split("\t", 2)
      next if sha.blank? || CommitRecord.exists?(sha: sha)

      CommitRecord.create!(sha: sha, message: message.to_s, author: ticket.agent&.name || "claude",
                           committed_at: Time.current)
    end
  end

  DIFF_LINES = 40

  def capture_diff(repo)
    base = GitRepo.base_branch(repo) || "HEAD~1"
    # Three dots is already merge-base relative: the diff shows what this
    # branch added, not what the base branch moved on to.
    out, ok = git(repo, "diff", "#{base}...HEAD", "--unified=1")
    out, ok = git(repo, "diff", "HEAD~1", "--unified=1") unless ok && out.present?
    lines = ok ? out.lines : []

    rendered = lines.first(DIFF_LINES).map { |raw| diff_line(raw.chomp) }
    if lines.size > DIFF_LINES
      rendered << diff_line("… #{lines.size - DIFF_LINES} more lines — read the branch for the rest")
    end
    rendered.concat(stranded_lines(repo))
    return if rendered.empty?

    ticket.update!(diff: rendered)
  end

  def diff_line(line)
    style =
      case line
      when /\A\+/ then { "bg" => "var(--ok-soft)", "fg" => "var(--ok)" }
      when /\A-/  then { "bg" => "var(--err-soft)", "fg" => "var(--err)" }
      when /\A@@/ then { "bg" => "var(--sunken)", "fg" => "var(--info)" }
      else             { "bg" => "transparent", "fg" => "var(--tx2)" }
      end
    style.merge("line" => line)
  end

  # Work the agent left uncommitted is work the pull request will not contain.
  # It is invisible in the branch diff, so say so where the diff is read.
  def stranded_lines(repo)
    stranded = GitRepo.uncommitted(repo)
    return [] if stranded.empty?

    Event.record!(phase_tag: tag, tone: "var(--warn)", ticket: ticket, agent: ticket.agent,
                  meta: "uncommitted",
                  text: "#{ticket.code}: #{stranded.size} file(s) changed but never committed — " \
                        "they will not be in the pull request")
    warn = { "bg" => "var(--warn-soft)", "fg" => "var(--warn)" }
    [warn.merge("line" => "── uncommitted, and therefore NOT in the pull request ──")] +
      stranded.first(10).map { |f| warn.merge("line" => "#{f['status']} #{f['path']}") }
  end

  def capture_plan_artifact
    plan = "openspec/changes/#{ticket.code.downcase}-plan.md"
    path = Workspace.repo_path(ticket.repo)
    return unless path && File.exist?(File.join(path, plan))

    ticket.update!(artifacts: ticket.artifacts | [plan])
  end

  # A run that hit its turn limit or its timeout is usually a run that did
  # most of the work — it committed, it answered, it just never got to say so.
  # Discarding all of it means the retry starts from nothing and the money is
  # spent twice. Keep what reached disk; the ticket still fails.
  def salvage(repo, result)
    capture_outputs(repo)
    # Keep what the run reported, but never let a failed run reroute the
    # ticket: it is about to be marked failed and would leave two live runs.
    handle_structured_output(result, reroute: false)
    return unless (kept = salvaged_note)

    Event.record!(phase_tag: tag, tone: "var(--warn)", ticket: ticket, agent: ticket.agent,
                  meta: "salvaged", text: "Kept from the failed #{phase} run: #{kept}")
  rescue StandardError => e
    # Salvage is best-effort — never let it mask the failure it is salvaging.
    Rails.logger.warn { "salvage failed for run #{run.id}: #{e.class}: #{e.message}" }
  end

  def salvaged_note
    parts = []
    parts << "#{ticket.diff.size} diff lines" if ticket.diff.any?
    pending = Question.pending.where(ticket_code: ticket.code, phase: phase).count
    parts << "#{pending} clarification question(s)" if pending.positive?
    parts << "test results" if run.tests_executed?
    parts << "the plan" if phase == "planning" && ticket.acceptance_criteria.any?
    parts.join(", ").presence
  end

  # Grooming contracts (PhasePrompts): investigation may raise clarification
  # questions; planning reports change ref, board dependencies and splits;
  # review reports findings and a verdict. Read from the run's out-file first
  # so a truncated run still reports (PhaseOutput).
  def handle_structured_output(result, reroute: true)
    data = PhaseOutput.read(run, result&.result_text)
    return unless data

    case phase
    when "investigation" then create_questions(data)
    when "planning"      then apply_plan_output(data)
    when "review"        then apply_review_output(data, reroute: reroute)
    when "testing"       then capture_test_results(data)
    end
  ensure
    PhaseOutput.clear(run)
  end

  # How many times implementation may be sent back before the machine stops
  # arguing with itself and the operator decides.
  REWORK_LIMIT = 2

  # The reviewer reports; implementation fixes. A blocking finding therefore
  # has to move the ticket, or review is a phase that produces prose and
  # changes nothing.
  def apply_review_output(data, reroute: true)
    findings = Array(data["findings"]).filter_map do |f|
      next unless f.is_a?(Hash)

      what = f["what"].to_s.strip.presence or next
      { "severity" => (f["severity"].to_s == "blocking" ? "blocking" : "minor"),
        "file" => f["file"].to_s.truncate(120).presence,
        "what" => what.truncate(300), "why" => f["why"].to_s.truncate(300).presence }.compact
    end
    blocking = findings.select { |f| f["severity"] == "blocking" }
    verdict = blocking.any? ? "changes_requested" : "pass"
    run.update!(review_findings: findings, review_verdict: verdict,
                note: review_note(findings, verdict))
    Event.record!(phase_tag: "REVIEW", tone: blocking.any? ? "var(--warn)" : "var(--ok)",
                  ticket: ticket, agent: ticket.agent, meta: verdict.tr("_", " "),
                  text: "Review of #{ticket.code}: #{review_note(findings, verdict)}")
    return if blocking.empty?

    feedback = blocking.map { |f| "- #{f['file'] ? "#{f['file']} — " : ''}#{f['what']}" }.join("\n")
    ticket.update!(feedback: feedback)

    # Two rounds of rework is the machine's budget. Past that it keeps going
    # to testing carrying the unresolved findings, and the operator decides at
    # the verdict gate rather than watching it loop.
    rounds = ticket.phase_runs.where(phase: "implementation").count
    if rounds > REWORK_LIMIT
      Event.record!(phase_tag: "REVIEW", tone: "var(--err)", ticket: ticket, agent: ticket.agent,
                    meta: "unresolved",
                    text: "#{ticket.code} still has #{blocking.size} blocking finding(s) after " \
                          "#{rounds} implementation rounds — carrying them to your verdict")
      return
    end

    return unless reroute

    PipelineEngine.request_changes!(ticket, feedback)
    :rerouted
  end

  def review_note(findings, verdict)
    blocking = findings.count { |f| f["severity"] == "blocking" }
    minor = findings.size - blocking
    return "clean — nothing to change" if findings.empty?

    parts = []
    parts << "#{blocking} blocking" if blocking.positive?
    parts << "#{minor} minor" if minor.positive?
    "#{verdict == 'pass' ? 'passed' : 'changes requested'} · #{parts.join(', ')}".truncate(120)
  end

  def capture_test_results(data)
    # A repo where nothing could be run must never read as green. Previously
    # this returned early with no counts, tests_failed? stayed false, and a
    # non-draft pull request opened on work no suite ever touched.
    executed = data.key?("passed") || data.key?("failed")
    unless executed
      run.update!(tests_executed: false, note: "no suite ran — nothing verified this change")
      Event.record!(phase_tag: "TEST", tone: "var(--warn)", ticket: ticket, agent: ticket.agent,
                    text: "No tests ran for #{ticket.code} — the change is unverified")
      return
    end

    passed = data["passed"].to_i
    failed = data["failed"].to_i
    suites = Array(data["suites"]).filter_map do |s|
      next unless s.is_a?(Hash)

      { "kind" => s["kind"].to_s.presence || "tests", "command" => s["command"].to_s.truncate(120),
        "passed" => s["passed"], "failed" => s["failed"], "skipped" => s["skipped"].to_s.presence }.compact
    end

    run.update!(tests_command: data["command"].to_s.truncate(120).presence,
                tests_passed: passed, tests_failed: failed, test_suites: suites,
                tests_executed: true,
                note: suite_note(passed, failed, suites))
    suites.each do |s|
      next unless s["skipped"]

      Event.record!(phase_tag: "TEST", tone: "var(--warn)", ticket: ticket, agent: ticket.agent,
                    meta: s["kind"], text: "#{s['kind']} not run on #{ticket.code} — #{s['skipped']}")
    end
    Event.record!(phase_tag: "TEST", tone: failed.positive? ? "var(--warn)" : "var(--ok)",
                  ticket: ticket, agent: ticket.agent,
                  meta: data["command"].to_s.truncate(40).presence,
                  text: "Tests: #{passed} passed, #{failed} failed on #{ticket.code}")
  end

  # "128 passed · 0 failed · lint, unit, e2e" — the phase row should say what
  # was actually covered, not just a number.
  def suite_note(passed, failed, suites)
    note = "#{passed} passed · #{failed} failed"
    kinds = suites.map { |s| s["kind"] }.uniq
    note += " · #{kinds.join(', ')}" if kinds.any?
    skipped = suites.count { |s| s["skipped"] }
    note += " · #{skipped} not run" if skipped.positive?
    note.truncate(120)
  end

  def create_questions(data)
    Array(data["questions"]).first(2).each do |q|
      body = q["q"].to_s.strip.truncate(400)
      opts = Array(q["opts"]).first(4).map { |o| o.to_s.truncate(100) }
      next if body.blank? || opts.size < 2 || Question.pending.exists?(ticket_code: ticket.code, body: body)

      Question.create!(ticket_code: ticket.code, phase: phase, body: body,
                       options: opts, asked_at: Time.current)
    end
    return unless ticket.blocked_by_question?

    Event.record!(phase_tag: tag, tone: "var(--warn)", ticket: ticket, agent: ticket.agent,
                  meta: "clarification",
                  text: "#{ticket.code} needs your input before it can continue — see The Eye demands")
  end

  def apply_plan_output(data)
    change = data["change"].to_s.parameterize.presence
    ticket.update!(artifacts: ticket.artifacts | ["openspec change: #{change}"]) if change

    apply_enrichment(ticket, data)

    deps = Array(data["depends_on"]).map(&:to_s) &
           Ticket.where.not(code: ticket.code).pluck(:code)
    ticket.update!(dep_codes: ticket.dep_codes | deps) if deps.any?

    create_split_tickets(Array(data["additional_tickets"]), change)
  end

  # Shared with TicketEnrichJob: summary/notes/criteria out of a JSON payload.
  def self.apply_enrichment(ticket, data)
    updates = {}
    summary = data["summary"].to_s.strip
    updates[:description] = summary.truncate(1200) if summary.present? && ticket.description.blank?
    notes = data["technical_notes"].to_s.strip
    updates[:technical_notes] = notes.truncate(2000) if notes.present?
    criteria = Array(data["acceptance_criteria"]).map { |c| c.to_s.strip.truncate(200) }
                                                 .reject(&:blank?).first(8)
    updates[:acceptance_criteria] = criteria if criteria.any?
    ticket.update!(updates) if updates.any?
  end

  def apply_enrichment(ticket, data)
    self.class.apply_enrichment(ticket, data)
  end

  # "Allow split": planning may break an oversized ticket into follow-ups,
  # chained sequentially behind this one.
  def create_split_tickets(extras, change)
    extras = extras.first(4).select { |t| t["title"].to_s.strip.present? }
    return if extras.empty?

    number = Ticket.pluck(:code).filter_map { |c| c[/\d+/]&.to_i }.max.to_i
    previous = ticket.code
    extras.each do |extra|
      number += 1
      created = Ticket.create!(
        code: "ALG-#{number}", title: extra["title"].to_s.truncate(120), repo: ticket.repo,
        est_label: extra["estimate"].present? ? "~#{extra['estimate']}" : "—",
        risky: extra["risky"] == true, state: :ready_to_implement,
        dep_codes: [previous],
        artifacts: change ? ["openspec change: #{change}"] : []
      )
      previous = created.code
    end
    Event.record!(phase_tag: "PLAN", ticket: ticket, agent: ticket.agent,
                  text: "Plan split — #{extras.size} follow-up ticket(s) chained after #{ticket.code}")
  end

  def git(repo, *args)
    out, status = Open3.capture2("git", "-C", repo, *args, err: File::NULL)
    [out, status.success?]
  rescue Errno::ENOENT
    ["", false]
  end

  def fail_run(reason)
    run.update!(status: "failed", finished_at: Time.current, note: reason.to_s.truncate(200))
    ticket.agent&.update!(status: "waiting", doing: "#{ticket.code} #{phase} failed — #{reason.truncate(60)}")
    Event.record!(phase_tag: tag, tone: "var(--err)", ticket: ticket, agent: ticket.agent,
                  meta: "live run failed", text: "#{phase.capitalize} run failed: #{reason.truncate(140)}")
    PipelineEngine.broadcast
    false
  end
end
