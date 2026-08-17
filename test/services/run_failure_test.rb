require "test_helper"

# Every ticket in the first real run ended "failed" with the agent's last
# half-sentence as the explanation, and none of them recorded the money they
# had already spent. These cover both.
class RunFailureTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @repo = File.join(@dir, "sample-repo")
    FileUtils.mkdir_p(@repo)
    system("git", "init", "-q", @repo)
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t",
           "commit", "-qm", "init", "--allow-empty")

    ENV["WORKSPACE_ROOT"] = @dir
    ENV["CLAUDE_BIN"] = Rails.root.join("test/fixtures/files/fake_claude_maxturns").to_s
    ENV["PIPELINE_RUNNER"] = "auto"
    Workspace.refresh!
    Setting.instance.update!(running: true, autonomy: "auto", spend_cap: 80, setup_complete: true)
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    ENV.delete("CLAUDE_BIN")
    ENV["PIPELINE_RUNNER"] = "off"
    FileUtils.remove_entry(@dir)
  end

  def run_failing_phase
    ticket = Ticket.create!(code: "TST-F1", title: "Exhausts its turns",
                            repo: "sample-repo", state: :planning)
    run = ticket.phase_runs.create!(phase: "planning", status: "running",
                                    runner: "claude", started_at: Time.current)
    ClaudeCodeRunner.new(ticket, run).execute
    [ticket, run.reload]
  end

  test "a run that exhausts its turns is charged for what it spent" do
    _ticket, run = run_failing_phase

    assert_equal "failed", run.status
    assert_equal 4.3118, run.cost.to_f, "the failed run's real cost is recorded"
    assert_equal 4.3118, SpendEntry.total_today.to_f, "and reaches the ledger"
  end

  test "the failure explains itself instead of quoting the agent mid-sentence" do
    _ticket, run = run_failing_phase

    assert_match(/ran out of turns after 41/, run.note, "says why it stopped")
    refute_match(/Now let me run the critic/, run.note, "not the agent's dangling narration")
    assert_match(/permission/, run.note, "mentions the denied commands that burned turns")

    event = Event.where(phase_tag: "PLAN").order(:id).last
    assert_match(/ran out of turns/, event.text)
  end

  test "the ticket stays put and is retryable rather than advancing" do
    ticket, = run_failing_phase

    assert_equal "planning", ticket.reload.state, "a failed phase does not advance the ticket"
    assert_equal "failed", ticket.current_phase_run.status
  end

  test "the turn and time limits are high enough for real work" do
    assert_operator HeadlessAgent::DEFAULT_MAX_TURNS.to_i, :>=, 100,
                    "40 turns died mid-task on every real ticket"
    assert_operator HeadlessAgent::DEFAULT_TIMEOUT.to_i, :>=, 1800
  end

  test "agents may run linters and test suites" do
    refute_includes ClaudeCodeRunner::DEFAULT_FLAGS, "acceptEdits",
                    "acceptEdits denies Bash, so the testing phase could never run anything"
  end
end
