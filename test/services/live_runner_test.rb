require "test_helper"

class LiveRunnerTest < ActiveSupport::TestCase
  SPEC_MD = <<~MD
    # Kill Switch Specification

    ## Purpose
    Halt new order submission on drawdown breach.

    ## Requirements

    ### Requirement: Threshold breach halts submission
    The system SHALL reject new order intents when the drawdown threshold is breached.

    #### Scenario: Breach
    - **GIVEN** equity is down 8.1% intraday
    - **WHEN** a new long intent is submitted
    - **THEN** it is rejected with RISK_HALT

    ### Requirement: Re-arm requires a human
    The halt SHALL NOT clear automatically.
  MD

  setup do
    @dir = Dir.mktmpdir
    @repo = File.join(@dir, "demo-repo")
    FileUtils.mkdir_p(@repo)
    system("git", "init", "-q", @repo)
    system("git", "-C", @repo, "config", "user.email", "test@test")
    system("git", "-C", @repo, "config", "user.name", "test")
    File.write(File.join(@repo, "README.md"), "demo\n")
    system("git", "-C", @repo, "add", ".")
    system("git", "-C", @repo, "commit", "-qm", "initial commit")

    ENV["WORKSPACE_ROOT"] = @dir
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude").to_s
    ENV["PIPELINE_RUNNER"] = "auto"
    Workspace.refresh!
    Setting.instance.update!(running: true, autonomy: "auto", spend_today: 0, spend_cap: 80)
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    ENV.delete("CLAUDE_BIN")
    ENV["PIPELINE_RUNNER"] = "demo"
    FileUtils.remove_entry(@dir)
  end

  test "auth mode defaults to subscription and gates the credential source" do
    setting = Setting.instance
    assert_equal "subscription", setting.auth_mode

    Dir.mktmpdir do |config_dir|
      old_key = ENV.delete("ANTHROPIC_API_KEY")
      old_token = ENV.delete("CLAUDE_CODE_OAUTH_TOKEN")
      ENV["CLAUDE_CONFIG_DIR"] = config_dir
      begin
        refute ClaudeCodeRunner.subscription_credentials?
        File.write(File.join(config_dir, ".credentials.json"), "{}")
        assert ClaudeCodeRunner.subscription_credentials?
        assert ClaudeCodeRunner.auth_status(setting)[:ok]

        setting.update!(setup: setting.setup.merge("auth" => "1"))
        assert_equal "api_key", setting.auth_mode
        refute ClaudeCodeRunner.api_key?
        refute ClaudeCodeRunner.auth_status(setting)[:ok]

        ENV["ANTHROPIC_API_KEY"] = "sk-test-1234"
        assert ClaudeCodeRunner.api_key?
        assert ClaudeCodeRunner.auth_status(setting)[:ok]
      ensure
        ENV.delete("CLAUDE_CONFIG_DIR")
        old_key ? ENV["ANTHROPIC_API_KEY"] = old_key : ENV.delete("ANTHROPIC_API_KEY")
        old_token ? ENV["CLAUDE_CODE_OAUTH_TOKEN"] = old_token : ENV.delete("CLAUDE_CODE_OAUTH_TOKEN")
        setting.update!(setup: setting.setup.merge("auth" => "0"))
      end
    end
  end

  test "monorepo folder choice: root repo with sub-projects" do
    mono = File.join(@dir, "mono")
    FileUtils.mkdir_p(File.join(mono, "apps", "web"))
    File.write(File.join(mono, "apps", "web", "package.json"), "{}")
    FileUtils.mkdir_p(File.join(mono, "core"))
    File.write(File.join(mono, "core", "Gemfile"), "")
    system("git", "init", "-q", mono)
    system("git", "-C", mono, "add", ".")
    system("git", "-C", mono, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")

    Setting.instance.update!(setup: { "workspace_dir" => "mono" })
    assert_equal :monorepo, Workspace.layout
    assert_equal ["mono"], Workspace.repo_names

    subs = Workspace.subprojects(Workspace.repos.first)
    assert_includes subs, "core"
    assert_includes subs, "apps/web"
    assert_includes Workspace.ticket_targets, "mono/apps/web"
    assert_equal mono, Workspace.repo_path("mono/apps/web")
    assert_equal "apps/web", Workspace.subpath("mono/apps/web")
    assert_nil Workspace.subpath("mono")

    ticket = Ticket.new(code: "TST-M1", title: "Scoped work", repo: "mono/apps/web")
    assert_match(/`apps\/web` subdirectory/, PhasePrompts.build(ticket, "implementation"))
  end

  test "browse annotates folders and layout follows the chosen dir" do
    entries = Workspace.browse
    assert_equal ["demo-repo"], entries.map { |e| e[:name] }
    assert_equal :git_repo, entries.first[:kind]
    assert_equal :multi_repo, Workspace.layout

    Setting.instance.update!(setup: { "workspace_dir" => "demo-repo" })
    assert_equal :monorepo, Workspace.layout
    assert_equal "", Workspace.parent_rel
  end

  test "spec sync status explains why nothing was parsed" do
    spec_dir = File.join(@repo, "openspec", "specs", "kill-switch")
    FileUtils.mkdir_p(spec_dir)
    File.write(File.join(spec_dir, "spec.md"), SPEC_MD)
    Workspace.refresh!
    setting = Setting.instance

    # openspec repo exists but is unchecked → summary names the culprit
    setting.update!(setup: { "repo:demo-repo" => "false" })
    assert_equal 0, SpecSync.call(setting)
    summary = SpecSync.status_summary(setting, 0)
    assert_match(/demo-repo/, summary)
    assert_match(/unchecked/, summary)
    assert Event.exists?(["text LIKE ?", "%no openspec capabilities%"])

    # checked again → parses, reports progress and an unambiguous summary
    setting.update!(setup: {})
    Workspace.refresh!
    progress_calls = []
    count = SpecSync.call(setting, progress: ->(*args) { progress_calls << args })
    assert_equal 1, count
    assert_equal [[1, 1, "demo-repo/kill-switch"]], progress_calls
    assert_match(/all 1 spec file parsed/, SpecSync.status_summary(setting, count))
  end

  test "spec sync job publishes progress and clears it on completion" do
    spec_dir = File.join(@repo, "openspec", "specs", "kill-switch")
    FileUtils.mkdir_p(spec_dir)
    File.write(File.join(spec_dir, "spec.md"), SPEC_MD)
    Workspace.refresh!

    SpecSyncJob.perform_now

    setting = Setting.instance.reload
    assert_nil setting.setup["spec_sync_progress"], "progress marker must be cleared when done"
    assert_match(/all 1 spec file parsed/, setting.setup["last_spec_sync"])
    assert_equal 1, Capability.count
  end

  test "live mode activation purges demo data but keeps workspace tickets" do
    demo_ticket = Ticket.create!(code: "TST-D1", title: "Demo ticket", repo: "algo-core", state: :ready)
    real_ticket = Ticket.create!(code: "TST-R1", title: "Real ticket", repo: "demo-repo", state: :ready)
    CommitRecord.create!(sha: "abc1234", message: "demo commit", committed_at: Time.current)
    Question.create!(ticket_code: demo_ticket.code, body: "?", options: ["A"], asked_at: Time.current)
    Event.record!(phase_tag: "SYS", text: "demo event")
    agent = Agent.create!(name: "A1", abbr: "A1", role: "review", llm_model: "opus",
                          status: "running", cost_today: 5.0, doing: "busy with demo work")
    Setting.instance.update!(spend_today: 41.28)

    stages = []
    assert LiveMode.activate!(Setting.instance, progress: ->(stage, *_) { stages << stage })
    assert_equal %w[tickets history agents engine], stages.uniq, "staged progress in order"

    setting = Setting.instance.reload
    assert setting.live_mode?
    assert_match(/1 demo tickets purged · 1 workspace tickets kept/, setting.setup["live_mode_result"])
    assert_nil setting.setup["live_mode_progress"]
    assert_nil Ticket.find_by(code: "TST-D1"), "demo ticket must be purged"
    assert Ticket.exists?(code: "TST-R1"), "workspace ticket must survive"
    assert_equal 0, CommitRecord.count
    assert_equal 0, Question.count
    assert_equal 1, Event.count, "only the live-mode transition event remains"
    assert_equal 0, setting.spend_today
    assert_equal "idle", agent.reload.status

    # idempotent — a second activation must not purge again
    Event.record!(phase_tag: "SYS", text: "user event")
    assert LiveMode.activate!(setting)
    assert_equal 2, Event.count
  end

  test "live mode job clears its progress marker when done" do
    Ticket.create!(code: "TST-D9", title: "Demo leftover", repo: "algo-x", state: :ready)

    LiveModeJob.perform_now

    setting = Setting.instance.reload
    assert setting.live_mode?
    assert_nil setting.setup["live_mode_progress"]
    assert_match(/demo tickets purged/, setting.setup["live_mode_result"])
  end

  test "live mode engine never fabricates work and only pulls executable tickets" do
    Setting.instance.update!(live_mode: true)
    Agent.create!(name: "L1", abbr: "L1", role: "implementation", llm_model: "sonnet", status: "idle")
    stuck = Ticket.create!(code: "TST-X1", title: "Unresolvable", repo: "ghost-repo", state: :ready)
    live = Ticket.create!(code: "TST-Y1", title: "Executable", repo: "demo-repo", state: :ready)
    spend_before = Setting.instance.spend_today

    assert_no_difference -> { Ticket.count } do
      PipelineEngine.tick!
    end

    assert_equal "investigation", live.reload.state, "live-capable ticket gets picked up"
    assert_equal "claude", live.current_phase_run.runner
    assert_equal "ready", stuck.reload.state, "unresolvable ticket stays put"
    assert_equal spend_before, Setting.instance.reload.spend_today, "no simulated spend in live mode"
  end

  test "empty scan results are never cached" do
    empty_zone = File.join(@dir, "empty-zone")
    FileUtils.mkdir_p(empty_zone)
    Setting.instance.update!(setup: { "workspace_dir" => "empty-zone" })

    assert_empty Workspace.repos

    repo = File.join(empty_zone, "late-repo")
    FileUtils.mkdir_p(repo)
    system("git", "init", "-q", repo)
    # no refresh! — an empty result must not have been cached
    assert_equal ["late-repo"], Workspace.repo_names
  end

  test "orchestrator model defaults to opus 5 and rejects unknown values" do
    setting = Setting.instance
    assert_equal "claude-opus-5", setting.orchestrator_model

    setting.update!(setup: { "orchestrator_model" => "claude-sonnet-5" })
    assert_equal "claude-sonnet-5", setting.orchestrator_model

    setting.update!(setup: { "orchestrator_model" => "gpt-99" })
    assert_equal "claude-opus-5", setting.orchestrator_model, "unknown model falls back to default"
  end

  test "boot recovery fails orphaned rfc runs and clears job markers" do
    rfc = Rfc.create!(body: "orphaned", stage: 0, job_state: "investigating")
    setting = Setting.instance
    setting.update!(setup: setting.setup.merge(
      "spec_sync_progress" => { "done" => 1, "total" => 5, "at" => Time.current.to_i },
      "live_mode_progress" => { "stage" => "tickets", "at" => Time.current.to_i }
    ))

    BootRecovery.run!

    rfc.reload
    assert_equal "failed", rfc.job_state
    assert_match(/restart/, rfc.error)

    setting.reload
    assert_nil setting.setup["spec_sync_progress"]
    assert_nil setting.setup["live_mode_progress"]
    assert_match(/interrupted/, setting.setup["last_spec_sync"])
    assert_match(/interrupted/, setting.setup["live_mode_result"])
    assert Event.exists?(["text LIKE ?", "%interrupted by a restart%"])
  end

  test "engine sweeps silent live phase runs but leaves fresh ones alone" do
    stuck = Ticket.create!(code: "TST-S1", title: "Stuck run", repo: "demo-repo", state: :implementation)
    dead_run = stuck.phase_runs.create!(phase: "implementation", status: "running",
                                        runner: "claude", started_at: 2.hours.ago)
    dead_run.update_columns(updated_at: 2.hours.ago)

    fresh = Ticket.create!(code: "TST-S2", title: "Fresh run", repo: "demo-repo", state: :implementation)
    live_run = fresh.phase_runs.create!(phase: "implementation", status: "running",
                                        runner: "claude", started_at: Time.current)

    PipelineEngine.tick!

    assert_equal "failed", dead_run.reload.status
    assert_equal "running", live_run.reload.status
    assert Event.exists?(["text LIKE ?", "%went silent%"])
  end

  test "workspace scans are cached briefly and refreshable" do
    assert_equal ["demo-repo"], Workspace.repo_names

    second = File.join(@dir, "another-repo")
    FileUtils.mkdir_p(second)
    system("git", "init", "-q", second)

    assert_equal ["demo-repo"], Workspace.repo_names, "expected cached scan"
    Workspace.refresh!
    assert_equal ["another-repo", "demo-repo"], Workspace.repo_names
  end

  test "workspace root never escapes the mount" do
    Setting.instance.update!(setup: { "workspace_dir" => "../../etc" })
    assert_equal Workspace.mount_root, Workspace.root
  end

  test "workspace scans mounted git repos" do
    repos = Workspace.repos
    assert_equal ["demo-repo"], repos.map { |r| r[:name] }
    assert_equal 1, repos.first[:commits]
    assert_equal 1, repos.first[:files]
    assert_equal @repo, Workspace.repo_path("demo-repo")
    assert_nil Workspace.repo_path("missing-repo")
  end

  test "spec sync parses openspec capabilities from the workspace" do
    spec_dir = File.join(@repo, "openspec", "specs", "kill-switch")
    FileUtils.mkdir_p(spec_dir)
    File.write(File.join(spec_dir, "spec.md"), SPEC_MD)

    assert_equal 1, SpecSync.call

    capability = Capability.find_by!(slug: "demo-repo/kill-switch")
    assert_equal "Kill switch", capability.title
    assert_match(/drawdown breach/, capability.purpose)

    reqs = capability.spec_requirements.order(:position)
    assert_equal ["Threshold breach halts submission", "Re-arm requires a human"], reqs.map(&:name)
    assert_match(/SHALL reject/, reqs.first.body)

    scenario = reqs.first.spec_scenarios.first
    assert_equal "Scenario · Breach", scenario.name
    assert_match(/GIVEN equity is down/, scenario.body)
  end

  test "run phase job executes the stub CLI and advances the phase" do
    agent = Agent.create!(name: "Scout-L", abbr: "SL", role: "investigation",
                          llm_model: "sonnet", status: "running")
    ticket = Ticket.create!(code: "TST-77", title: "Live ticket", repo: "demo-repo",
                            state: :investigation, agent: agent)
    run = ticket.phase_runs.create!(phase: "investigation", status: "running",
                                    runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "investigation")

    run.reload
    assert_equal "done", run.status
    assert_equal 0, run.exit_status
    assert_equal "stub-session", run.session_id
    assert run.cost.positive?
    assert_includes run.log, "Root cause identified"

    ticket.reload
    assert_equal "planning", ticket.state
    assert_equal "claude", ticket.current_phase_run.runner

    assert Event.exists?(["text LIKE ?", "%Scanning repository%"])
    assert Event.exists?(["text LIKE ?", "%→ Read README.md%"])
    assert_in_delta 0.04, Setting.instance.spend_today.to_f, 0.02
    assert_equal "2k tok", ticket.tokens_label
  end

  test "live tickets are not advanced by demo tick thresholds" do
    ticket = Ticket.create!(code: "TST-78", title: "Live ticket", repo: "demo-repo",
                            state: :investigation,
                            phase_progress: Ticket::PHASE_THRESHOLDS["investigation"] + 5)
    ticket.phase_runs.create!(phase: "investigation", status: "running",
                              runner: "claude", started_at: Time.current)

    PipelineEngine.tick!
    assert_equal "investigation", ticket.reload.state
  end

  test "headless agent returns a structured result from the stub CLI" do
    result = HeadlessAgent.call(prompt: "hello", chdir: @repo)
    assert result.ok
    assert_equal "stub-session", result.session_id
    assert_in_delta 0.0421, result.cost, 0.001
    assert_includes result.result_text, "Root cause identified"
    assert result.raw.is_a?(Hash)
  end

  test "rfc investigation job parses trace and questions from a live run" do
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude_rfc").to_s
    Agent.create!(name: "Scout", abbr: "SC", role: "investigation", llm_model: "sonnet", status: "idle")
    rfc = Rfc.create!(body: "Add a farewell to greetings", job_state: "investigating")

    RfcInvestigateJob.perform_now(rfc.id)

    rfc.reload
    assert_equal 2, rfc.stage
    assert_equal "idle", rfc.job_state
    assert_equal 2, rfc.trace.size
    assert_equal "var(--warn)", rfc.trace.last["tone"]
    assert_equal 1, rfc.questions.size
    assert_equal "q1", rfc.questions.first["key"]
    assert_equal %w[Formal Casual], rfc.questions.first["opts"]
    assert Setting.instance.spend_today.positive?
    assert Event.exists?(["text LIKE ?", "%Investigation complete%"])
  end

  test "rfc plan job builds proposals and push allocates codes with deps" do
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude_rfc").to_s
    ENV["FAKE_MODE"] = "plan"
    Agent.create!(name: "Architect", abbr: "AR", role: "planning", llm_model: "opus", status: "idle")
    rfc = Rfc.create!(body: "Add a farewell", stage: 2, job_state: "planning",
                      questions: [{ "key" => "q1", "q" => "Tone?", "opts" => %w[Formal Casual] }],
                      answers: { "q1" => "Casual" })

    RfcPlanJob.perform_now(rfc.id)

    rfc.reload
    assert_equal 3, rfc.stage
    assert_equal 2, rfc.proposals.size
    assert_equal [1], rfc.proposals.last["dep_indexes"]

    rfc.push_to_board!
    codes = Ticket.order(:id).last(2).map(&:code)
    assert codes.all? { |c| c.match?(/\AALG-\d+\z/) }
    second = Ticket.find_by(code: codes.last)
    assert_equal [codes.first], second.dep_codes
    assert_equal "ready", second.state
    assert_equal "~30m", second.est_label
  ensure
    ENV.delete("FAKE_MODE")
  end

  def install_harness!
    base = File.join(@repo, ".claude")
    FileUtils.mkdir_p(File.join(base, "commands", "opsx"))
    %w[explore propose apply].each do |cmd|
      File.write(File.join(base, "commands", "opsx", "#{cmd}.md"), "# opsx #{cmd}")
    end
    FileUtils.mkdir_p(File.join(base, "skills", "review"))
    FileUtils.mkdir_p(File.join(base, "agents"))
    %w[explorer critic reviewer].each do |agent|
      File.write(File.join(base, "agents", "#{agent}.md"), "name: #{agent}")
    end
    Workspace.refresh!
  end

  test "harness detection maps commands, skills and agents onto phases" do
    install_harness!

    info = Harness.detect
    assert_equal "demo-repo", info.repo
    assert_includes info.commands, "opsx:explore"
    assert_includes info.skills, "review"
    assert_includes info.agents, "critic"

    assert_equal "/opsx:explore", Harness.phase_invocation("investigation")
    assert_equal "/opsx:propose", Harness.phase_invocation("planning")
    assert_equal "/review", Harness.phase_invocation("review"), "skill fallback"
    assert_nil Harness.phase_invocation("testing"), "no harness match stays built-in"
    assert_equal %w[explorer], Harness.phase_agents("investigation")
    assert_equal %w[reviewer critic], Harness.phase_agents("review") & %w[reviewer critic]

    Setting.instance.update!(setup: { "map:investigation" => "built-in" })
    assert_nil Harness.phase_invocation("investigation"), "override forces built-in"

    Setting.instance.update!(setup: { "fw" => "2" })
    assert_nil Harness.phase_invocation("planning"), "vanilla framework disables harness"
  end

  test "harness-mapped phases execute in the harness repo with workspace access" do
    install_harness!
    ticket = Ticket.new(code: "TST-H1", title: "Harness ticket", repo: "demo-repo", artifacts: [])

    plan = PhasePrompts.execution(ticket, "investigation", "/elsewhere")
    assert plan[:prompt].start_with?("/opsx:explore TST-H1"), plan[:prompt].lines.first
    assert_equal @repo, plan[:chdir]
    assert_includes plan[:extra_args], "--add-dir"
    assert_includes plan[:prompt], "explorer", "suggests matching project agents"

    # implementation needs a change ref — without one it falls back to built-in
    fallback = PhasePrompts.execution(ticket, "implementation", "/elsewhere")
    refute fallback[:prompt].start_with?("/opsx:apply")
    assert_equal "/elsewhere", fallback[:chdir]

    ticket.artifacts = ["openspec change: add-farewell"]
    apply_plan = PhasePrompts.execution(ticket, "implementation", "/elsewhere")
    assert apply_plan[:prompt].start_with?("/opsx:apply add-farewell")
    assert_equal @repo, apply_plan[:chdir]
  end

  test "rfc flow through the harness records the openspec change" do
    install_harness!
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude_rfc").to_s
    Agent.create!(name: "Architect", abbr: "AR", role: "planning", llm_model: "opus", status: "idle")
    rfc = Rfc.create!(body: "Add a farewell", stage: 2, job_state: "planning")

    assert RfcPrompts.plan(rfc, ["demo-repo"]).start_with?("/opsx:propose"), "harness planning prompt"

    RfcPlanJob.perform_now(rfc.id)

    rfc.reload
    assert_equal 3, rfc.stage
    assert_equal "add-farewell", rfc.proposals.first["change"]

    rfc.push_to_board!
    ticket = Ticket.order(:id).last
    assert_includes ticket.artifacts, "openspec change: add-farewell"
  end

  test "workspace recent commits merges selected repos newest first" do
    File.write(File.join(@repo, "second.txt"), "x")
    system("git", "-C", @repo, "add", ".")
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "second commit")
    Workspace.refresh!

    commits = Workspace.recent_commits(Setting.instance, limit: 5)
    assert_equal ["second commit", "initial commit"], commits.map(&:message)
    assert_equal "demo-repo", commits.first.author
    assert commits.first.committed_at >= commits.last.committed_at
  end

  test "failed run marks the phase and can fall back on retry" do
    ticket = Ticket.create!(code: "TST-79", title: "Broken ticket", repo: "missing-repo",
                            state: :implementation)
    run = ticket.phase_runs.create!(phase: "implementation", status: "running",
                                    runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "implementation")

    assert_equal "failed", run.reload.status
    assert Event.exists?(["text LIKE ?", "%run failed%"])
  end
end
