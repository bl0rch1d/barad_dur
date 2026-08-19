require "test_helper"

# "main, else master" is a guess, and it is wrong for every project whose trunk
# is named something else — and worse for one that renamed to main and left a
# stale master behind.
class GitRepoTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    git("init", "-q", "-b", "develop")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "Test")
    File.write(File.join(@repo, "README.md"), "hello\n")
    git("add", "-A")
    git("commit", "-qm", "first")
  end

  teardown { FileUtils.remove_entry(@repo) }

  def git(*args)
    out, status = Open3.capture2e("git", "-C", @repo, *args)
    [out, status.success?]
  end

  test "a repo whose trunk is develop is not diffed against something else" do
    assert_equal "develop", GitRepo.base_branch(@repo)
  end

  test "a stale master does not outrank the branch the remote calls HEAD" do
    git("branch", "master")
    git("branch", "main")
    git("remote", "add", "origin", "https://example.com/x.git")
    git("update-ref", "refs/remotes/origin/main", "HEAD")
    git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")

    assert_equal "main", GitRepo.base_branch(@repo),
                 "the remote's own answer outranks the conventional names"
  end

  test "conventional names are the last resort, in order" do
    git("branch", "master")
    git("checkout", "-q", "master")
    git("branch", "-D", "develop")

    assert_equal "master", GitRepo.base_branch(@repo)
  end

  test "a repo with no recognisable base says so rather than guessing" do
    git("branch", "-m", "develop", "some-odd-name")

    assert_nil GitRepo.base_branch(@repo)
  end

  test "uncommitted work is reported, because a pull request will not contain it" do
    File.write(File.join(@repo, "new_file.rb"), "puts 1\n")
    File.write(File.join(@repo, "README.md"), "changed\n")

    stranded = GitRepo.uncommitted(@repo).sort_by { |f| f["path"] }

    assert_equal %w[README.md new_file.rb], stranded.map { |f| f["path"] }
    assert_equal "??", stranded.last["status"], "a file never added is the one most easily lost"
  end

  test "a clean repo reports nothing stranded" do
    assert_empty GitRepo.uncommitted(@repo)
  end

  test "a path that is not a git repo degrades quietly" do
    assert_nil GitRepo.base_branch("/nonexistent-path-here")
    assert_empty GitRepo.uncommitted("/nonexistent-path-here")
  end

  test "a work branch is cut from the base, not from whatever was checked out last" do
    git("checkout", "-q", "-b", "pipe/other-ticket")
    File.write(File.join(@repo, "other.rb"), "# another ticket's work\n")
    git("add", "-A")
    git("commit", "-qm", "another ticket's commit")

    ticket = Ticket.create!(code: "TST-B1", title: "Fresh", repo: "sample-repo", state: :implementation)
    run_record = ticket.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)
    ClaudeCodeRunner.new(ticket, run_record).send(:prepare_branch, @repo)

    log, = git("log", "--oneline")
    refute_match(/another ticket's commit/, log,
                 "branching from HEAD gives every ticket the previous one's commits")
    assert_match(%r{pipe/tst-b1}, git("rev-parse", "--abbrev-ref", "HEAD").first)
  end
end
