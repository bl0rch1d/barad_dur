require "test_helper"

class ScreensTest < ActionDispatch::IntegrationTest
  setup do
    Setting.instance.update!(setup_complete: true)
  end

  test "all screens render" do
    [root_path, board_path, rfc_path, specs_path, agents_path, activity_path].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
  end

  test "ticket drawer renders over any screen" do
    ticket = Ticket.create!(code: "TST-9", title: "Drawer ticket", repo: "sample-repo", state: :ready)
    get root_path(ticket: ticket.code)
    assert_response :success
    assert_includes response.body, "Drawer ticket"
  end

  test "wizard renders each step" do
    (1..5).each do |step|
      get root_path(wizard: step)
      assert_response :success
    end
  end

  test "autonomy toggle updates the setting" do
    post settings_autonomy_path(value: "every")
    assert_redirected_to root_path
    assert_equal "every", Setting.instance.autonomy

    post settings_autonomy_path(value: "bogus")
    assert_equal "every", Setting.instance.autonomy
  end

  test "run toggle flips running and restarting over cap resets spend" do
    Setting.instance.update!(running: false, spend_today: 100, spend_cap: 80)
    post settings_toggle_run_path
    setting = Setting.instance
    assert setting.running?
    assert_equal 0, setting.spend_today
  end

  test "sending a chat message enqueues the architect reply" do
    assert_enqueued_with(job: ChatReplyJob) do
      post chat_messages_path, params: { body: "Weight fill quality above latency" }
    end
    assert_redirected_to activity_path(room: "workspace")
    assert_equal 1, ChatMessage.where(sender: "you").count
  end

  test "answering a question records the decision" do
    question = Question.create!(ticket_code: "TST-1", phase: "review", body: "Which?",
                                options: ["A", "B"], asked_at: Time.current)
    post answer_question_path(question, option: "B")
    assert_equal "B", question.reload.chosen
    assert_equal "answered", question.status
  end

  test "wizard patch stores whitelisted keys only" do
    post wizard_patch_path(key: "fw", value: "1")
    assert_equal "1", Setting.instance.setup["fw"]

    post wizard_patch_path(key: "evil", value: "x")
    assert_nil Setting.instance.setup["evil"]

    post wizard_patch_path(key: "orchestrator_model", value: "claude-haiku-4-5")
    assert_equal "claude-haiku-4-5", Setting.instance.orchestrator_model
  end

  test "specs sync enqueues the parse job once while in flight" do
    assert_enqueued_with(job: SpecSyncJob) { post specs_sync_path }
    assert Setting.instance.setup["spec_sync_progress"].present?

    assert_no_enqueued_jobs(only: SpecSyncJob) { post specs_sync_path }
  end

  test "dashboard action center shows gates, failed runs and live telemetry" do
    gated = Ticket.create!(code: "TST-DG", title: "Gated ticket", state: :ready_to_implement)
    gate = gated.ticket_gates.create!(to_state: Ticket::STATES[:implementation],
                                      reason: "TST-DG is ready — approve to start implementation.")
    failed = Ticket.create!(code: "TST-DF", title: "Failed ticket", state: :implementation)
    failed.phase_runs.create!(phase: "implementation", status: "failed", runner: "claude",
                              note: "exit 1", started_at: 5.minutes.ago)
    done_run = Ticket.create!(code: "TST-DR", title: "Telemetry ticket", state: :review)
    done_run.phase_runs.create!(phase: "implementation", status: "done", runner: "claude",
                                started_at: 10.minutes.ago, duration_s: 300, cost: 0.42)

    get root_path
    assert_response :success
    assert_includes response.body, "approve to start implementation"
    assert_includes response.body, "✓ Approve"
    assert_includes response.body, "↻ Retry"
    assert_includes response.body, "Recent agent runs"
    assert_includes response.body, "TST-DR"
    assert_includes response.body, "Agent runs"

    post approve_gate_path(gate)
    assert_equal "implementation", gated.reload.state
  end

  test "an unbound realm shows the LOTR empty state with a wizard button" do
    Setting.instance.update!(setup_complete: false)

    [root_path, board_path, rfc_path, specs_path, agents_path, activity_path].each do |path|
      get path
      assert_response :success
      assert_includes response.body, "Bind the realm — Setup wizard", "expected empty state on #{path}"
    end
    get board_path
    assert_includes response.body, "Even Sauron cannot micromanage an empty land"
    refute_includes response.body, "board-wrap", "board content hidden until setup"

    # the wizard itself still opens over the empty state
    get root_path(wizard: 1)
    assert_includes response.body, "Choose the workspace"
  end

  test "tickets can be edited while parked and deleted unless running" do
    ticket = Ticket.create!(code: "TST-ED1", title: "Old title", repo: "sample-repo",
                            state: :ready_to_implement)
    other = Ticket.create!(code: "TST-ED2", title: "Dep target", state: :draft)

    patch ticket_path("TST-ED1"), params: { title: "New title", description: "Details",
                                            risky: "1", dep_codes: "TST-ED2, GHOST-1" }
    ticket.reload
    assert_equal "New title", ticket.title
    assert_equal "Details", ticket.description
    assert ticket.risky?
    assert_equal ["TST-ED2"], ticket.dep_codes, "unknown dep codes dropped"

    running = Ticket.create!(code: "TST-ED3", title: "Running", state: :implementation)
    running.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)
    patch ticket_path("TST-ED3"), params: { title: "Nope" }
    assert_equal "Running", running.reload.title, "in-flight tickets are not editable"

    delete ticket_path("TST-ED3")
    assert Ticket.exists?(code: "TST-ED3"), "running ticket cannot be deleted"

    Question.create!(ticket_code: "TST-ED1", body: "?", options: %w[A B], asked_at: Time.current)
    delete ticket_path("TST-ED1")
    refute Ticket.exists?(code: "TST-ED1")
    assert_equal 0, Question.where(ticket_code: "TST-ED1").count
    assert_redirected_to board_path
  end

  test "ticket repo is clamped to the wizard's selected targets" do
    post tickets_path, params: { title: "Clamped draft", repo: "not-in-workspace" }
    ticket = Ticket.order(:id).last
    assert_equal "Clamped draft", ticket.title
    refute_equal "not-in-workspace", ticket.repo, "unselected repo must not be filed into"

    existing = Ticket.create!(code: "TST-CL1", title: "Keeper", repo: "legacy-repo", state: :draft)
    patch ticket_path("TST-CL1"), params: { repo: "sneaky-repo" }
    assert_equal "legacy-repo", existing.reload.repo, "repo edits outside selected targets are ignored"

    patch ticket_path("TST-CL1"), params: { repo: "legacy-repo", title: "Keeper 2" }
    assert_equal "legacy-repo", existing.reload.repo, "a ticket's current repo stays assignable"
    assert_equal "Keeper 2", existing.title
  end

  test "shipped view lists done tickets and attention badge counts blockers" do
    done = Ticket.create!(code: "TST-SH1", title: "Shipped work", repo: "sample-repo",
                          state: :done, finished_at: 1.hour.ago, cost: 1.5)
    get board_path(shipped: 1)
    assert_response :success
    assert_includes response.body, "Shipped work"

    Question.create!(ticket_code: done.code, body: "?", options: %w[A B], asked_at: Time.current)
    gated = Ticket.create!(code: "TST-SH2", title: "Gated", state: :ready_to_implement)
    gated.ticket_gates.create!(to_state: Ticket::STATES[:implementation], reason: "gate")

    get root_path
    assert_match(/data-attention-count-value="2"/, response.body)
  end

  test "review actions are gated to review and later states" do
    implementing = Ticket.create!(code: "TST-RG1", title: "Still coding", state: :implementation)
    get root_path(ticket: implementing.code)
    assert_response :success
    refute_includes response.body, "tickets/#{implementing.code}/merge"
    assert_includes response.body, "review actions unlock"

    reviewing = Ticket.create!(code: "TST-RG2", title: "In review", state: :review)
    get root_path(ticket: reviewing.code)
    assert_response :success
    assert_includes response.body, "Approve &amp; merge"
  end

  test "wizard workspace_dir accepts relative folders and rejects traversal" do
    post wizard_patch_path(key: "workspace_dir", value: "sub/folder")
    assert_equal "sub/folder", Setting.instance.setup["workspace_dir"]

    post wizard_patch_path(key: "workspace_dir", value: "../evil")
    assert_equal "sub/folder", Setting.instance.setup["workspace_dir"]

    post wizard_patch_path(key: "workspace_dir", value: "/etc")
    assert_equal "sub/folder", Setting.instance.setup["workspace_dir"]

    post wizard_patch_path(key: "workspace_dir", value: "")
    assert_equal "", Setting.instance.setup["workspace_dir"]
  end
end
