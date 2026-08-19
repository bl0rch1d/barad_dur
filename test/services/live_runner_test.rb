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
    @repo = File.join(@dir, "sample-repo")
    FileUtils.mkdir_p(@repo)
    system("git", "init", "-q", @repo)
    system("git", "-C", @repo, "config", "user.email", "test@test")
    system("git", "-C", @repo, "config", "user.name", "test")
    File.write(File.join(@repo, "README.md"), "sample\n")
    system("git", "-C", @repo, "add", ".")
    system("git", "-C", @repo, "commit", "-qm", "initial commit")

    ENV["WORKSPACE_ROOT"] = @dir
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude").to_s
    ENV["PIPELINE_RUNNER"] = "auto"
    Workspace.refresh!
    Setting.instance.update!(running: true, autonomy: "auto", spend_cap: 80)
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    ENV.delete("CLAUDE_BIN")
    ENV["PIPELINE_RUNNER"] = "off"
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

  test "unchecking a repo removes it from targets, harness detection and ticket clamps" do
    second = File.join(@dir, "aaa-other")
    FileUtils.mkdir_p(File.join(second, ".claude", "commands", "opsx"))
    File.write(File.join(second, ".claude", "commands", "opsx", "explore.md"), "# explore")
    system("git", "init", "-q", second)
    system("git", "-C", second, "add", ".")
    system("git", "-C", second, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
    Workspace.refresh!

    setting = Setting.instance
    assert_equal %w[aaa-other sample-repo], Workspace.repo_names
    assert_equal "aaa-other", Harness.detect(setting).repo

    setting.update!(setup: setting.setup.merge("repo:aaa-other" => "false"))
    assert_equal %w[sample-repo], Workspace.selected_repos(setting).map { |r| r[:name] }
    assert_equal %w[sample-repo], Workspace.selected_ticket_targets(setting)
    assert_nil Harness.detect(setting), "harness must not come from an unchecked repo"
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
    assert_equal ["sample-repo"], entries.map { |e| e[:name] }
    assert_equal :git_repo, entries.first[:kind]
    assert_equal :multi_repo, Workspace.layout

    Setting.instance.update!(setup: { "workspace_dir" => "sample-repo" })
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
    setting.update!(setup: { "repo:sample-repo" => "false" })
    assert_equal 0, SpecSync.call(setting)
    summary = SpecSync.status_summary(setting, 0)
    assert_match(/sample-repo/, summary)
    assert_match(/unchecked/, summary)
    assert Event.exists?(["text LIKE ?", "%no openspec capabilities%"])

    # checked again → parses, reports progress and an unambiguous summary
    setting.update!(setup: {})
    Workspace.refresh!
    progress_calls = []
    count = SpecSync.call(setting, progress: ->(*args) { progress_calls << args })
    assert_equal 1, count
    assert_equal [[1, 1, "sample-repo/kill-switch"]], progress_calls
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
      "spec_sync_progress" => { "done" => 1, "total" => 5, "at" => Time.current.to_i }
    ))

    BootRecovery.run!

    rfc.reload
    assert_equal "failed", rfc.job_state
    assert_match(/restart/, rfc.error)

    setting.reload
    assert_nil setting.setup["spec_sync_progress"]
    assert_match(/interrupted/, setting.setup["last_spec_sync"])
    assert Event.exists?(["text LIKE ?", "%interrupted by a restart%"])
  end

  test "engine sweeps silent live phase runs but leaves fresh ones alone" do
    stuck = Ticket.create!(code: "TST-S1", title: "Stuck run", repo: "sample-repo", state: :implementation)
    dead_run = stuck.phase_runs.create!(phase: "implementation", status: "running",
                                        runner: "claude", started_at: 2.hours.ago)
    dead_run.update_columns(updated_at: 2.hours.ago)

    fresh = Ticket.create!(code: "TST-S2", title: "Fresh run", repo: "sample-repo", state: :implementation)
    live_run = fresh.phase_runs.create!(phase: "implementation", status: "running",
                                        runner: "claude", started_at: Time.current)

    PipelineEngine.tick!

    assert_equal "failed", dead_run.reload.status
    assert_equal "running", live_run.reload.status
    assert Event.exists?(["text LIKE ?", "%went silent%"])
  end

  test "workspace scans are cached briefly and refreshable" do
    assert_equal ["sample-repo"], Workspace.repo_names

    second = File.join(@dir, "another-repo")
    FileUtils.mkdir_p(second)
    system("git", "init", "-q", second)

    assert_equal ["sample-repo"], Workspace.repo_names, "expected cached scan"
    Workspace.refresh!
    assert_equal ["another-repo", "sample-repo"], Workspace.repo_names
  end

  test "workspace root never escapes the mount" do
    Setting.instance.update!(setup: { "workspace_dir" => "../../etc" })
    assert_equal Workspace.mount_root, Workspace.root
  end

  test "workspace scans mounted git repos" do
    repos = Workspace.repos
    assert_equal ["sample-repo"], repos.map { |r| r[:name] }
    assert_equal 1, repos.first[:commits]
    assert_equal 1, repos.first[:files]
    assert_equal @repo, Workspace.repo_path("sample-repo")
    assert_nil Workspace.repo_path("missing-repo")
  end

  test "spec sync parses openspec capabilities from the workspace" do
    spec_dir = File.join(@repo, "openspec", "specs", "kill-switch")
    FileUtils.mkdir_p(spec_dir)
    File.write(File.join(spec_dir, "spec.md"), SPEC_MD)

    assert_equal 1, SpecSync.call

    capability = Capability.find_by!(slug: "sample-repo/kill-switch")
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
    ticket = Ticket.create!(code: "TST-77", title: "Live ticket", repo: "sample-repo",
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
    assert_equal "ready_to_implement", second.state
    assert_equal "~30m", second.est_label
  ensure
    ENV.delete("FAKE_MODE")
  end

  def install_harness!
    base = File.join(@repo, ".claude")
    FileUtils.mkdir_p(File.join(base, "commands", "opsx"))
    %w[explore propose apply archive].each do |cmd|
      File.write(File.join(base, "commands", "opsx", "#{cmd}.md"), "# opsx #{cmd}")
    end
    FileUtils.mkdir_p(File.join(base, "skills", "review"))
    FileUtils.mkdir_p(File.join(base, "agents"))
    %w[explorer planner critic reviewer].each do |agent|
      File.write(File.join(base, "agents", "#{agent}.md"),
                 "---\nname: #{agent}\ndescription: #{agent} specialist for tests\n---\n")
    end
    Workspace.refresh!
  end

  test "harness detection maps commands, skills and agents onto phases" do
    install_harness!

    info = Harness.detect
    assert_equal "sample-repo", info.repo
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
    ticket = Ticket.new(code: "TST-H1", title: "Harness ticket", repo: "sample-repo", artifacts: [])

    plan = PhasePrompts.execution(ticket, "investigation", "/elsewhere")
    assert plan[:prompt].start_with?("/opsx:explore TST-H1"), plan[:prompt].lines.first
    assert_equal @repo, plan[:chdir]
    assert_includes plan[:extra_args], "--add-dir"
    assert_includes plan[:prompt], "explorer", "suggests matching project agents"

    # a repo with no openspec still gets the harness for implementation — the
    # ticket identifies the work when there is no change slug to pass
    no_change = PhasePrompts.execution(ticket, "implementation", "/elsewhere")
    assert no_change[:prompt].start_with?("/opsx:apply TST-H1: Harness ticket"), no_change[:prompt].lines.first
    assert_equal @repo, no_change[:chdir]
    assert_includes no_change[:prompt], "/elsewhere", "the harness must be told where the code is"

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

    assert RfcPrompts.plan(rfc, ["sample-repo"]).start_with?("/opsx:propose"), "harness planning prompt"

    RfcPlanJob.perform_now(rfc.id)

    rfc.reload
    assert_equal 3, rfc.stage
    assert_equal "add-farewell", rfc.proposals.first["change"]

    rfc.push_to_board!
    ticket = Ticket.order(:id).last
    assert_includes ticket.artifacts, "openspec change: add-farewell"
  end

  def write_stub!(payload_json)
    result = { type: "result", subtype: "success", is_error: false,
               total_cost_usd: 0.01, duration_ms: 500, usage: {},
               result: "Done.\n```json\n#{payload_json}\n```" }.to_json
    path = File.join(@dir, "stub_claude")
    File.write(path, "#!/usr/bin/env bash\n" \
                     "printf '%s\\n' \"$@\" > '#{@dir}/stub_args.txt'\n" \
                     "echo '{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s\",\"model\":\"stub\"}'\n" \
                     "echo '#{result}'\n")
    FileUtils.chmod("+x", path)
    ENV["CLAUDE_BIN"] = path
  end

  test "chat reply job answers, stores the session and resumes it" do
    write_stub!("{}")
    Agent.create!(name: "Architect", abbr: "AR", role: "planning", llm_model: "opus", status: "idle")

    first = ChatMessage.create!(room: "workspace", sender: "you",
                                body: "What is the state of the workspace?", sent_at: Time.current)
    ChatReplyJob.perform_now(first.id)

    reply = ChatMessage.in_room("workspace").last
    assert_equal "architect", reply.sender
    assert_includes reply.body, "Done."
    assert_equal "s", Setting.instance.reload.setup["chat_session:workspace"]
    args = File.read(File.join(@dir, "stub_args.txt"))
    refute_match(/--resume/, args, "first message starts a fresh session")
    assert_match(/You are the Architect/, args, "opening prompt carries the intro")

    second = ChatMessage.create!(room: "workspace", sender: "you",
                                 body: "And the tests?", sent_at: Time.current)
    ChatReplyJob.perform_now(second.id)
    args = File.read(File.join(@dir, "stub_args.txt"))
    assert_match(/--resume/, args, "follow-up resumes the stored session")
    assert_match(/^s$/, args)
    refute_match(/You are the Architect/, args, "resumed sessions skip the intro")
  ensure
  end

  test "grooming investigation with questions parks the ticket and resumes on answers" do
    write_stub!('{"questions":[{"q":"Which auth flow?","why":"changes scope","opts":["OAuth","API key"]}]}')
    agent = Agent.create!(name: "Scout-G", abbr: "SG", role: "investigation",
                          llm_model: "sonnet", status: "running")
    ticket = Ticket.create!(code: "TST-Q1", title: "Groomed draft", repo: "sample-repo",
                            state: :investigation, agent: agent)
    ticket.phase_runs.create!(phase: "investigation", status: "running",
                              runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "investigation")

    ticket.reload
    assert_equal "investigation", ticket.state, "parked, not transitioned"
    assert_equal "clarification", ticket.blocker[:type]
    assert_equal "done", ticket.current_phase_run.status
    question = Question.pending.find_by(ticket_code: "TST-Q1")
    assert_equal ["OAuth", "API key"], question.options

    PipelineEngine.answer_question!(question, "OAuth")
    assert_equal "planning", ticket.reload.state, "resumes after the answer"
  end

  test "testing runs capture pass/fail counts" do
    write_stub!('{"command":"bin/rails test","passed":42,"failed":1}')
    ticket = Ticket.create!(code: "TST-TR1", title: "Test capture", repo: "sample-repo", state: :testing)
    run = ticket.phase_runs.create!(phase: "testing", status: "running",
                                    runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "testing")

    run.reload
    assert_equal "bin/rails test", run.tests_command
    assert_equal 42, run.tests_passed
    assert_equal 1, run.tests_failed
    assert_match(/42 passed · 1 failed/, run.note)
    assert Event.exists?(["text LIKE ?", "%Tests: 42 passed, 1 failed%"])
  end

  test "grooming planning captures change, deps and split tickets" do
    other = Ticket.create!(code: "TST-DEP", title: "Existing work", repo: "sample-repo", state: :implementation)
    write_stub!('{"change":"add-auth","depends_on":["TST-DEP"],"additional_tickets":[{"title":"Wire auth into UI","estimate":"30m","risky":false}]}')
    ticket = Ticket.create!(code: "TST-P1", title: "Add auth", repo: "sample-repo", state: :planning)
    ticket.phase_runs.create!(phase: "planning", status: "running",
                              runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "planning")

    ticket.reload
    assert_equal "ready_to_implement", ticket.state
    assert_includes ticket.artifacts, "openspec change: add-auth"
    assert_includes ticket.dep_codes, "TST-DEP"
    assert_equal "dependency", ticket.blocker[:type], "waits on TST-DEP"

    split = Ticket.order(:id).last
    assert_equal "Wire auth into UI", split.title
    assert_equal "ready_to_implement", split.state
    assert_equal [ticket.code], split.dep_codes
    assert_includes split.artifacts, "openspec change: add-auth"
  end

  def git!(*args)
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t", *args,
           out: File::NULL, err: File::NULL)
  end

  test "approve & merge lands the work branch and completes the ticket" do
    ticket = Ticket.create!(code: "TST-M1", title: "Mergeable work", repo: "sample-repo", state: :review)
    git!("checkout", "-b", "pipe/tst-m1")
    File.write(File.join(@repo, "feature.txt"), "new feature\n")
    git!("add", ".")
    git!("commit", "-m", "add feature")

    result = BranchMerger.call(ticket)
    assert result.ok, result.message
    PipelineEngine.manual_ship!(ticket, result.message)

    out, = Open3.capture2("git", "-C", @repo, "log", "--oneline", "-3")
    assert_match(/Merge pipe\/tst-m1/, out)
    assert File.exist?(File.join(@repo, "feature.txt")), "merged file present on base branch"
    ticket.reload
    assert_equal "done", ticket.state
    assert ticket.finished_at.present?
    assert Event.exists?(["text LIKE ?", "%approved & merged%"])
  end

  test "merge conflict aborts cleanly and reports failure" do
    ticket = Ticket.create!(code: "TST-M2", title: "Conflicting work", repo: "sample-repo", state: :review)
    git!("checkout", "-b", "pipe/tst-m2")
    File.write(File.join(@repo, "README.md"), "branch version\n")
    git!("commit", "-am", "branch edit")
    git!("checkout", "master")
    File.write(File.join(@repo, "README.md"), "master version\n")
    git!("commit", "-am", "master edit")

    result = BranchMerger.call(ticket)
    refute result.ok
    assert_match(/conflict/, result.message)
    assert_equal "review", ticket.reload.state, "ticket untouched on failed merge"
    out, = Open3.capture2("git", "-C", @repo, "status", "--porcelain")
    assert_equal "", out.strip, "repo left clean after aborted merge"
  end

  test "request changes sends the ticket back to implementation with feedback" do
    ticket = Ticket.create!(code: "TST-RC1", title: "Needs rework", repo: "sample-repo", state: :review)
    ticket.phase_runs.create!(phase: "review", status: "running", runner: "claude", started_at: Time.current)

    PipelineEngine.request_changes!(ticket, "Use arrival price, not mid price")

    ticket.reload
    assert_equal "implementation", ticket.state
    assert_equal "Use arrival price, not mid price", ticket.feedback
    run = ticket.current_phase_run
    assert_equal "implementation", run.phase
    assert_equal "claude", run.runner
    assert_match(/rework/, run.note)
    assert Event.exists?(["text LIKE ?", "%Changes requested on TST-RC1%"])
    assert_includes PhasePrompts.build(ticket, "implementation"), "arrival price"
  end

  test "agent roster maps harness agents onto phases with defaults filling gaps" do
    install_harness!
    orphan = Agent.create!(name: "Old-Stray", abbr: "OS", role: "misc", llm_model: "sonnet",
                           status: "idle", position: 9)
    ticket = Ticket.create!(code: "TST-AR1", title: "Assigned", state: :implementation, agent: orphan)
    6.times { |i| Agent.create!(name: "Surplus-#{i}", abbr: "S#{i}", role: "misc", llm_model: "x", position: i) }

    roster = AgentRoster.rebuild!

    assert_equal %w[explorer planner Builder reviewer Tester Shipper], roster.map(&:name)
    assert_equal Ticket::PHASES, roster.map(&:role)
    assert_equal 6, Agent.count, "extras removed"
    assert_nil ticket.reload.agent_id, "orphaned assignment detached, ticket intact"

    specialists = AgentRoster.specialists
    assert_includes specialists.map { |s| s[:name] }, "critic", "unmapped harness agents are specialists"
    refute_includes specialists.map { |s| s[:name] }, "explorer", "roster members are not specialists"

    assert_equal "explorer", Agent.for_phase("investigation").name
    assert_equal "planner", Agent.for_phase("planning").name
  end

  test "selected ticket targets honor the wizard repo selection" do
    assert_equal ["sample-repo"], Workspace.selected_ticket_targets

    Setting.instance.update!(setup: { "repo:sample-repo" => "false" })
    assert_empty Workspace.selected_ticket_targets
    assert_equal ["sample-repo"], Workspace.ticket_targets, "unselected repos remain visible to full listing"
  end

  test "grooming planning stores summary, notes and acceptance criteria" do
    write_stub!('{"change":"add-auth","summary":"Adds auth.","technical_notes":"Touch lib/auth.rb.","acceptance_criteria":["Login works","Logout works"],"depends_on":[],"additional_tickets":[]}')
    ticket = Ticket.create!(code: "TST-EN1", title: "Add auth", repo: "sample-repo", state: :planning)
    ticket.phase_runs.create!(phase: "planning", status: "running", runner: "claude", started_at: Time.current)

    RunPhaseJob.perform_now(ticket.id, "planning")

    ticket.reload
    assert_equal "Adds auth.", ticket.description
    assert_equal "Touch lib/auth.rb.", ticket.technical_notes
    assert_equal ["Login works", "Logout works"], ticket.acceptance_criteria
  end

  test "enrich job backfills an existing ticket and clears its marker" do
    write_stub!('{"summary":"Backfilled summary.","technical_notes":"Notes.","acceptance_criteria":["It ships"]}')
    ticket = Ticket.create!(code: "TST-EN2", title: "Legacy ticket", repo: "sample-repo", state: :ready_to_implement)
    Setting.instance.update!(setup: { "enrich:TST-EN2" => Time.current.to_i })

    TicketEnrichJob.perform_now(ticket.id)

    ticket.reload
    assert_equal "Backfilled summary.", ticket.description
    assert_equal ["It ships"], ticket.acceptance_criteria
    assert_nil Setting.instance.reload.setup["enrich:TST-EN2"], "marker cleared"
    assert Event.exists?(["text LIKE ?", "%TST-EN2 enriched%"])
  end

  test "archive job runs the harness archive command after a merge" do
    install_harness!
    write_stub!("{}")
    ticket = Ticket.create!(code: "TST-AC1", title: "Merged work", repo: "sample-repo", state: :done,
                            artifacts: ["openspec change: add-auth"])

    ArchiveChangeJob.perform_now(ticket.id)

    args = File.read(File.join(@dir, "stub_args.txt"))
    assert_match(%r{/opsx:archive add-auth}, args)
    assert_includes ticket.reload.artifacts, "change archived: add-auth"
    assert Event.exists?(["text LIKE ?", "%add-auth archived into the permanent spec tree%"])
  end

  test "archive job no-ops without a change ref or archive command" do
    write_stub!("{}")
    plain = Ticket.create!(code: "TST-AC2", title: "No change", repo: "sample-repo", state: :done)
    assert_no_difference -> { Event.count } do
      ArchiveChangeJob.perform_now(plain.id)
    end
  end

  test "push & PR pushes the branch to origin and opens a pull request" do
    # a bare origin + a gh stub that records its args and prints a PR URL
    origin = File.join(@dir, "origin.git")
    system("git", "init", "-q", "--bare", origin)
    git!("remote", "add", "origin", origin)
    git!("checkout", "-b", "pipe/tst-pr1")
    File.write(File.join(@repo, "pr.txt"), "x")
    git!("add", ".")
    git!("commit", "-m", "pr work")

    gh_stub = File.join(@dir, "gh_stub")
    File.write(gh_stub, "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > '#{@dir}/gh_args.txt'\n" \
                        "echo 'https://github.com/example/sample-repo/pull/7'\n")
    FileUtils.chmod("+x", gh_stub)
    ENV["GH_BIN"] = gh_stub

    ticket = Ticket.create!(code: "TST-PR1", title: "PR work", repo: "sample-repo", state: :review,
                            description: "Adds the thing.", acceptance_criteria: ["Thing works"])
    PushPrJob.perform_now(ticket.id)

    out, = Open3.capture2("git", "-C", origin, "for-each-ref", "--format=%(refname:short)")
    assert_includes out, "pipe/tst-pr1", "branch pushed to origin"
    gh_args = File.read(File.join(@dir, "gh_args.txt"))
    assert_match(/pr\ncreate/, gh_args)
    assert_match(/TST-PR1: PR work/, gh_args)
    assert_match(/Thing works/, gh_args)
    assert_includes ticket.reload.artifacts, "PR: https://github.com/example/sample-repo/pull/7"
    assert Event.exists?(["text LIKE ?", "%Pull request opened for TST-PR1%"])
  ensure
    ENV.delete("GH_BIN")
  end

  test "push & PR fails cleanly without an origin remote" do
    git!("checkout", "-b", "pipe/tst-pr2")
    ticket = Ticket.create!(code: "TST-PR2", title: "No remote", repo: "sample-repo", state: :review)
    PushPrJob.perform_now(ticket.id)
    assert Event.exists?(["text LIKE ?", "%no origin remote%"])
  end

  test "workspace recent commits merges selected repos newest first" do
    File.write(File.join(@repo, "second.txt"), "x")
    system("git", "-C", @repo, "add", ".")
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "second commit")
    Workspace.refresh!

    commits = Workspace.recent_commits(Setting.instance, limit: 5)
    assert_equal ["second commit", "initial commit"], commits.map(&:message)
    assert_equal "sample-repo", commits.first.author
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
