require "test_helper"

# The bundled harness's agents are delegates — spawned inside a run and never
# assigned a ticket. Letting them name the roster would rename the Builder to
# "fixer" and the Critic to "review-unit" in every realm, since the bundled
# harness now always staffs something.
class AgentRosterNamingTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["WORKSPACE_ROOT"] = @dir
    @setting = Setting.instance
    @setting.update!(setup: {})
    Workspace.refresh!
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    Workspace.refresh!
    FileUtils.remove_entry(@dir)
  end

  def user_harness!(*agents)
    repo = File.join(@dir, "myrepo")
    FileUtils.mkdir_p(File.join(repo, ".claude/agents"))
    Open3.capture2e("git", "-C", repo, "init", "-q")
    FileUtils.mkdir_p(File.join(repo, ".claude/skills/explore"))
    File.write(File.join(repo, ".claude/skills/explore/SKILL.md"), "---\nname: explore\n---\n")
    agents.each do |agent|
      File.write(File.join(repo, ".claude/agents/#{agent}.md"),
                 "---\nname: #{agent}\ndescription: #{agent}\n---\n")
    end
    @setting.update!(setup: @setting.setup.merge("repo:myrepo" => "true"))
    Workspace.refresh!
    repo
  end

  test "with only the bundled harness, the roster keeps its own names" do
    roster = AgentRoster.rebuild!(@setting).index_by(&:role)

    assert_equal "Scout", roster["investigation"].name
    assert_equal "Builder", roster["implementation"].name, "fixer is a review delegate, not the Builder"
    assert_equal "Critic", roster["review"].name, "review-unit is spawned by review, it is not review"
    assert_equal "Shipper", roster["deployment"].name
  end

  test "the bundled agents are still offered as delegates" do
    assert_includes Harness.phase_agents("review", @setting), "review-verifier"
    assert_includes AgentRoster.specialists(@setting).map { |s| s[:name] }, "scout"
  end

  test "a harness the user brought does name the phases it staffs" do
    user_harness!("explorer")

    roster = AgentRoster.rebuild!(@setting).index_by(&:role)

    assert_equal "explorer", roster["investigation"].name
    assert_includes roster["investigation"].tools.first, "myrepo"
  end

  test "phases that user harness does not staff keep the default names" do
    user_harness!("explorer")

    roster = AgentRoster.rebuild!(@setting).index_by(&:role)

    assert_equal "Tester", roster["testing"].name,
                 "testing is staffed by the bundled backstop, which does not get to rename it"
    assert_equal "Critic", roster["review"].name
  end

  test "the roster is always exactly the six phases" do
    AgentRoster.rebuild!(@setting)

    assert_equal Ticket::PHASES, Agent.order(:position).map(&:role)
  end
end
