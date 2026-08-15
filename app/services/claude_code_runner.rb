require "open3"
require "json"
require "shellwords"

# Executes one pipeline phase as a real headless Claude Code run inside the
# ticket's workspace repository (process handling lives in HeadlessAgent).
# Streams the agent's messages into the live event feed, accounts real cost,
# captures commits/diff, then hands the ticket back to PipelineEngine for the
# (possibly gated) transition.
class ClaudeCodeRunner
  DEFAULT_FLAGS = "--permission-mode acceptEdits".freeze
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
    plan = PhasePrompts.execution(ticket, phase, repo)
    harness_run = plan[:chdir] != repo
    Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent,
                  meta: harness_run ? "harness run" : "live run",
                  text: "Started #{phase} run (#{harness_run ? plan[:prompt].lines.first.to_s.strip.truncate(40) : 'claude code'})")

    result = HeadlessAgent.call(prompt: plan[:prompt], chdir: plan[:chdir],
                                extra_args: plan[:extra_args], env: child_env) do |data|
      case data["type"]
      when "system"
        run.update!(session_id: data["session_id"]) if data["session_id"]
      when "assistant"
        narrate(data)
      end
    end

    run.update!(log: result.log.to_s.last(50_000), exit_status: result.exit_status,
                cost: result.cost.to_f)

    if result.ok
      accrue_cost(result.raw)
      capture_outputs(repo)
      Event.record!(phase_tag: tag, ticket: ticket, agent: ticket.agent,
                    meta: run_meta(result.raw),
                    text: "#{phase.capitalize} run finished — #{summary(result.raw)}")
      PipelineEngine.phase_finished!(ticket)
    else
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
    DemoScript::TAGS.fetch(phase, "IMPL")
  end

  # Implementation happens on a dedicated work branch; later phases keep
  # operating on it because it stays checked out.
  def prepare_branch(repo)
    return unless phase == "implementation"

    branch = "pipe/#{ticket.code.downcase}"
    created = system("git", "-C", repo, "checkout", "-B", branch, out: File::NULL, err: File::NULL)
    ticket.update!(artifacts: ticket.artifacts | ["branch #{branch}"]) if created
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

    setting = Setting.instance
    setting.update!(spend_today: (setting.spend_today + cost).round(2))
    SpendSample.accrue!(cost)
    ticket.agent&.increment!(:cost_today, cost.round(2))
    ticket.increment!(:cost, cost.round(2))

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

  def capture_diff(repo)
    base = %w[main master].find { |b| git(repo, "rev-parse", "--verify", b).last } || "HEAD~1"
    out, ok = git(repo, "diff", "#{base}...HEAD", "--unified=1")
    out, ok = git(repo, "diff", "HEAD~1", "--unified=1") unless ok && out.present?
    return unless ok && out.present?

    lines = out.lines.first(40).map do |raw|
      line = raw.chomp
      style =
        case line
        when /\A\+/ then { "bg" => "var(--ok-soft)", "fg" => "var(--ok)" }
        when /\A-/  then { "bg" => "var(--err-soft)", "fg" => "var(--err)" }
        when /\A@@/ then { "bg" => "var(--sunken)", "fg" => "var(--info)" }
        else             { "bg" => "transparent", "fg" => "var(--tx2)" }
        end
      style.merge("line" => line)
    end
    ticket.update!(diff: lines)
  end

  def capture_plan_artifact
    plan = "openspec/changes/#{ticket.code.downcase}-plan.md"
    path = Workspace.repo_path(ticket.repo)
    return unless path && File.exist?(File.join(path, plan))

    ticket.update!(artifacts: ticket.artifacts | [plan])
  end

  def git(repo, *args)
    out, status = Open3.capture2("git", "-C", repo, *args, err: File::NULL)
    [out, status.success?]
  rescue Errno::ENOENT
    ["", false]
  end

  def fail_run(reason)
    run.update!(status: "failed", finished_at: Time.current)
    ticket.agent&.update!(status: "waiting", doing: "#{ticket.code} #{phase} failed — #{reason.truncate(60)}")
    Event.record!(phase_tag: tag, tone: "var(--err)", ticket: ticket, agent: ticket.agent,
                  meta: "live run failed", text: "#{phase.capitalize} run failed: #{reason.truncate(140)}")
    PipelineEngine.broadcast
    false
  end
end
