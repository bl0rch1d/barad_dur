require "test_helper"

class AgentConfigTest < ActionDispatch::IntegrationTest
  setup do
    # an empty workspace, so no harness is detected and the panel shows the
    # built-in path — otherwise this asserts against whatever repo is mounted
    @dir = Dir.mktmpdir
    ENV["WORKSPACE_ROOT"] = @dir
    Workspace.refresh!
    Setting.instance.update!(setup_complete: true, setup: { "orchestrator_model" => "claude-opus-5" })
    @agent = Agent.create!(name: "Scout", abbr: "SC", role: "investigation",
                           llm_model: "opus 5", position: 0, tools: ["ripgrep"])
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    Workspace.refresh!
    FileUtils.remove_entry(@dir)
  end

  test "an agent card opens a panel explaining the role and where it runs" do
    get agents_path(agent: @agent.id)

    assert_response :success
    assert_includes response.body, "Reads the code before anything is decided"
    assert_includes response.body, "Where this agent is used"
    assert_includes response.body, "built-in investigation prompt"
    assert_includes response.body, "follow realm"
  end

  test "an agent follows the realm until it is pinned" do
    assert_equal "claude-opus-5", @agent.effective_model
    refute @agent.pinned?

    post agent_model_path(@agent, model: "claude-haiku-4-5")

    @agent.reload
    assert @agent.pinned?
    assert_equal "claude-haiku-4-5", @agent.effective_model
    assert_equal "Haiku 4.5", @agent.model_label
  end

  test "clearing the pin returns the agent to the realm setting" do
    @agent.update!(model_id: "claude-sonnet-5")

    post agent_model_path(@agent, model: "")

    refute @agent.reload.pinned?
    assert_equal "claude-opus-5", @agent.effective_model,
                 "and it moves again when the realm setting changes"
  end

  test "an unknown model is refused" do
    post agent_model_path(@agent, model: "gpt-4")
    refute @agent.reload.pinned?
  end

  test "a pinned agent's model is what its phase actually runs on" do
    @agent.update!(model_id: "claude-haiku-4-5")
    ticket = Ticket.create!(code: "TST-M1", title: "Pinned", state: :investigation, agent: @agent)

    assert_equal "claude-haiku-4-5", ticket.agent.effective_model,
                 "ClaudeCodeRunner passes this to HeadlessAgent as --model"
  end
end
