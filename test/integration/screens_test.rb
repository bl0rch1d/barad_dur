require "test_helper"

class ScreensTest < ActionDispatch::IntegrationTest
  test "all screens render" do
    [root_path, board_path, rfc_path, specs_path, agents_path, activity_path].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
  end

  test "ticket drawer renders over any screen" do
    ticket = Ticket.create!(code: "TST-9", title: "Drawer ticket", repo: "algo-core", state: :ready)
    get root_path(ticket: ticket.code)
    assert_response :success
    assert_includes response.body, "Drawer ticket"
  end

  test "wizard renders each step" do
    (1..6).each do |step|
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
    assert_enqueued_with(job: ArchitectReplyJob) do
      post chat_messages_path, params: { body: "Weight fill quality above latency" }
    end
    assert_redirected_to activity_path
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
