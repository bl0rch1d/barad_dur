require "test_helper"

# Two things had to change before the bundled harness could ever run: the
# global "vanilla" switch silently disabled it, and resolution was wholesale,
# so a partial user harness left the remaining phases on built-in prompts.
class HarnessResolutionTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    # The real workspace is mounted in this environment and carries a harness
    # of its own, which would make every assertion below about the wrong thing.
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

  # A repo carrying only some of the six skills — the case that used to leave
  # the remaining phases on built-in prompts.
  def install_partial_harness!(*skills)
    repo = File.join(@dir, "myrepo")
    # Workspace only counts a git checkout as a repo.
    FileUtils.mkdir_p(repo)
    Open3.capture2e("git", "-C", repo, "init", "-q")
    skills.each do |skill|
      FileUtils.mkdir_p(File.join(repo, ".claude/skills", skill))
      File.write(File.join(repo, ".claude/skills", skill, "SKILL.md"), "---\nname: #{skill}\n---\n")
    end
    @setting.update!(setup: @setting.setup.merge("repo:myrepo" => "true"))
    Workspace.refresh!
    repo
  end

  test "a realm that chose vanilla no longer silently disables the harness" do
    @setting.update!(setup: @setting.setup.merge("fw" => "2"))

    assert Harness.active?(@setting), "vanilla predates the shipped harness; it must not veto it"
    assert Harness.phase_invocation("review", @setting)
  end

  test "the reinterpretation happens once, at boot, and says so" do
    @setting.update!(setup: @setting.setup.merge("fw" => "2"))

    BootRecovery.send(:reinterpret_vanilla_framework)

    assert_equal "1", Setting.instance.setup["fw"]
    event = Event.where(meta: "framework").last
    assert_match(/vanilla/i, event.text)
    assert_match(/Settings/, event.text, "and points at the way back")
  end

  test "reinterpreting is idempotent — a realm that never chose vanilla is untouched" do
    @setting.update!(setup: @setting.setup.merge("fw" => "0"))

    BootRecovery.send(:reinterpret_vanilla_framework)

    assert_equal "0", Setting.instance.setup["fw"]
    assert_nil Event.where(meta: "framework").last
  end

  test "a per-phase built-in override still works, and is the way to opt out" do
    @setting.update!(setup: @setting.setup.merge("map:review" => "built-in"))

    assert_nil Harness.phase_invocation("review", @setting)
    assert_equal "/test", Harness.phase_invocation("testing", @setting), "other phases are unaffected"
  end

  test "the wizard can still show what an overridden phase would have resolved to" do
    @setting.update!(setup: @setting.setup.merge("map:review" => "built-in"))

    assert_equal "/review", Harness.default_invocation("review", @setting),
                 "an override should read as a choice, not as an absence"
    assert_equal({ "map:review" => "built-in" }.merge(@setting.setup), @setting.setup,
                 "and computing it must not mutate the realm's settings")
  end

  test "with no harness of its own, every phase falls to the bundled one" do
    %w[investigation planning implementation review testing deployment].each do |phase|
      invocation, info = Harness.source_for(phase, @setting)
      assert invocation, "#{phase} resolved to nothing"
      assert info.bundled?, "#{phase} should be staffed by the bundled harness"
    end
  end

  test "a partial user harness keeps its phases and the rest fall to the bundled one" do
    repo = install_partial_harness!("explore", "propose")

    inv, inv_info = Harness.source_for("investigation", @setting)
    plan, plan_info = Harness.source_for("planning", @setting)
    test_inv, test_info = Harness.source_for("testing", @setting)

    assert_equal "/explore", inv
    assert_equal repo, inv_info.path, "the user's own skill, in the user's own repo"
    assert_equal "/propose", plan
    refute plan_info.bundled?

    assert_equal "/test", test_inv, "the phase it does not cover must not drop to a built-in prompt"
    assert test_info.bundled?
  end

  test "a phase staffed by the backstop runs in the backstop's directory" do
    install_partial_harness!("explore")
    ticket = Ticket.create!(code: "TST-HR", title: "t", repo: "myrepo", state: :testing)

    plan = PhasePrompts.execution(ticket, "testing", "/some/repo", @setting)

    assert_equal Harness.bundled.path, plan[:chdir],
                 "chdir came from detect(), so a backstop phase ran in the wrong harness"
  end

  test "a partial harness offers each phase the delegates of whichever harness staffs it" do
    install_partial_harness!("explore")

    assert_includes Harness.phase_agents("review", @setting), "review-unit",
                    "the bundled review skill can only prompt the bundled agents"
  end
end
