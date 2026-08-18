require "test_helper"

# Auto-detection takes the first selected repo that carries a harness. These
# cover choosing a different one — including a directory outside the
# selection, or a sub-project inside a repo.
class HarnessChoiceTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    ENV["WORKSPACE_ROOT"] = @dir
    Workspace.refresh!
    @setting = Setting.instance
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    Workspace.refresh!
    FileUtils.remove_entry(@dir)
  end

  def repo_with_harness(name, command:, nested: nil)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.join(path, ".claude", "commands", "opsx"))
    File.write(File.join(path, ".claude", "commands", "opsx", "#{command}.md"), "# #{command}")
    system("git", "init", "-q", path)
    system("git", "-C", path, "-c", "user.email=t@t", "-c", "user.name=t",
           "commit", "-qm", "init", "--allow-empty")

    if nested
      sub = File.join(path, nested, ".claude", "commands")
      FileUtils.mkdir_p(sub)
      File.write(File.join(sub, "apply.md"), "# apply")
    end
    Workspace.refresh!
    path
  end

  test "auto-detection picks the first selected repo carrying a harness" do
    repo_with_harness("aaa-repo", command: "explore")
    repo_with_harness("zzz-repo", command: "propose")

    assert_equal "aaa-repo", Harness.detect(@setting).repo
    assert_equal "/opsx:explore", Harness.default_invocation("investigation", @setting)
  end

  test "choosing a directory overrides what auto-detection found" do
    repo_with_harness("aaa-repo", command: "explore")
    repo_with_harness("zzz-repo", command: "propose")

    @setting.update!(setup: @setting.setup.merge("harness_dir" => "zzz-repo"))

    assert_equal "zzz-repo", Harness.detect(@setting).repo
    assert_equal "/opsx:propose", Harness.default_invocation("planning", @setting)
    assert_nil Harness.default_invocation("investigation", @setting), "the chosen harness has no explore"
  end

  test "a chosen directory is used even when its repo is unselected" do
    repo_with_harness("aaa-repo", command: "explore")
    repo_with_harness("zzz-repo", command: "propose")
    @setting.update!(setup: @setting.setup.merge("repo:zzz-repo" => "false"))

    listing = Harness.available(@setting).detect { |c| c[:rel] == "zzz-repo" }
    refute listing[:selected], "the listing marks it as outside the selection"

    @setting.update!(setup: @setting.setup.merge("harness_dir" => "zzz-repo"))
    assert_equal "zzz-repo", Harness.detect(@setting).repo,
                 "an explicit choice is consent, unlike silent auto-detection"
  end

  test "available lists every harness in the workspace, including sub-projects" do
    repo_with_harness("mono", command: "explore", nested: "packages")
    repo_with_harness("other", command: "propose")

    rels = Harness.available(@setting).map { |c| c[:rel] }
    assert_includes rels, "mono"
    assert_includes rels, "other"
    assert_includes rels, "mono/packages", "a sub-project one level inside a repo is offered too"

    listing = Harness.available(@setting).detect { |c| c[:rel] == "mono" }
    assert_equal 1, listing[:commands]
    assert listing[:selected]
  end

  test "a directory with no harness falls back to auto-detection" do
    repo_with_harness("aaa-repo", command: "explore")
    FileUtils.mkdir_p(File.join(@dir, "empty-dir"))
    Workspace.refresh!

    @setting.update!(setup: @setting.setup.merge("harness_dir" => "empty-dir"))
    assert_equal "aaa-repo", Harness.detect(@setting).repo
  end

  test "a chosen path cannot escape the workspace" do
    repo_with_harness("aaa-repo", command: "explore")

    @setting.update!(setup: @setting.setup.merge("harness_dir" => "../../etc"))
    assert_nil Harness.scan_path("../../etc", @setting)
    assert_equal "aaa-repo", Harness.detect(@setting).repo, "falls back rather than reaching outside"
  end
end
