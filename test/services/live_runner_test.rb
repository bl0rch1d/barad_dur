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
