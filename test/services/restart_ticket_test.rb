require "test_helper"

# Retrying resumes the failed phase and keeps everything before it. Restarting
# is for when what came before is not worth resuming from — so it has to
# actually discard that, or the fresh run inherits conclusions it never reached.
class RestartTicketTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    ENV["WORKSPACE_ROOT"] = @repo
    FileUtils.mkdir_p(File.join(@repo, "sample-repo"))
    Open3.capture2e("git", "-C", File.join(@repo, "sample-repo"), "init", "-q")
    Workspace.refresh!

    @agent = Agent.create!(name: "Scout", abbr: "SC", role: "investigation",
                           status: "running", llm_model: "opus", doing: "working")
    @ticket = Ticket.create!(code: "TST-RS", title: "Cache metadata", repo: "sample-repo",
                             state: :review, agent: @agent,
                             description: "Backtests refetch metadata.",
                             technical_notes: "from planning",
                             acceptance_criteria: ["it caches"],
                             dep_codes: %w[TST-OTHER], artifacts: ["openspec change: x"],
                             feedback: "the reviewer said no", pr_url: "https://example.com/pr/1",
                             diff: [{ "line" => "+x" }], tokens_label: "9k tok",
                             started_at: 1.hour.ago, cost: 4.25)
    @ticket.phase_runs.create!(phase: "investigation", status: "done", started_at: 2.hours.ago)
    @ticket.phase_runs.create!(phase: "review", status: "failed", started_at: 1.hour.ago)
  end

  teardown do
    ENV.delete("WORKSPACE_ROOT")
    Workspace.refresh!
    FileUtils.remove_entry(@repo)
  end

  def code_dir = File.join(@repo, "sample-repo", ".pipe", "TST-RS")

  test "the ticket goes back to the start of the pipeline" do
    PipelineEngine.restart!(@ticket)

    assert_equal "ready", @ticket.reload.state
    assert_nil @ticket.started_at
  end

  test "what the pipeline concluded is discarded" do
    PipelineEngine.restart!(@ticket)
    @ticket.reload

    assert_empty @ticket.acceptance_criteria, "criteria came from a planning run that is being redone"
    assert_nil @ticket.technical_notes
    assert_nil @ticket.feedback
    assert_empty @ticket.dep_codes
    assert_empty @ticket.artifacts
    assert_empty @ticket.diff
    assert_nil @ticket.pr_url
  end

  test "what the human wrote is kept" do
    PipelineEngine.restart!(@ticket)
    @ticket.reload

    assert_equal "Cache metadata", @ticket.title
    assert_equal "Backtests refetch metadata.", @ticket.description
    assert_equal "sample-repo", @ticket.repo
  end

  test "the money already spent is not erased" do
    PipelineEngine.restart!(@ticket)

    assert_equal 4.25, @ticket.reload.cost, "the ledger records what was spent, restart or not"
  end

  test "old runs go, so the board does not show phases this attempt never reached" do
    PipelineEngine.restart!(@ticket)

    assert_empty @ticket.reload.phase_runs, "a done investigation row would say it is already groomed"
  end

  test "questions and gates from the discarded attempt do not survive it" do
    Question.create!(ticket_code: "TST-RS", phase: "investigation", asked_at: 1.hour.ago,
                     body: "still open?", options: %w[A B])
    @ticket.ticket_gates.create!(to_state: Ticket::STATES[:done], reason: "waiting")

    PipelineEngine.restart!(@ticket)

    assert_empty Question.pending.where(ticket_code: "TST-RS")
    refute @ticket.reload.gated?
  end

  test "an answered question survives — it is a decision, not an artifact" do
    Question.create!(ticket_code: "TST-RS", phase: "investigation", asked_at: 2.hours.ago,
                     body: "memory or disk?", options: %w[Memory Disk], chosen: "Disk",
                     status: "answered")

    PipelineEngine.restart!(@ticket)

    assert_equal 1, Question.where(ticket_code: "TST-RS").where.not(chosen: nil).count
  end

  test "the previous record is moved aside, not deleted, and not inherited" do
    FileUtils.mkdir_p(code_dir)
    File.write(File.join(code_dir, "record.md"), "## Intent\n\nthe old attempt\n")

    PipelineEngine.restart!(@ticket)

    refute File.exist?(File.join(code_dir, "record.md")),
           "a fresh investigation would append to full sections and degraded would report nothing missing"
    archived = Dir.glob("#{code_dir}-*").first
    assert archived, "the only account of the failed attempt must not be thrown away"
    assert_includes File.read(File.join(archived, "record.md")), "the old attempt"
  end

  test "the agent is released" do
    PipelineEngine.restart!(@ticket)

    assert_equal "idle", @agent.reload.status
  end

  test "it says what happened, and where the old record went" do
    PipelineEngine.restart!(@ticket)

    event = Event.where(meta: "restarted").last
    assert_match(/restarted from the beginning/, event.text)
  end

  test "a ticket whose repo is gone still restarts rather than raising" do
    @ticket.update!(repo: "no-such-repo")

    assert_nothing_raised { PipelineEngine.restart!(@ticket) }
    assert_equal "ready", @ticket.reload.state
  end
end
