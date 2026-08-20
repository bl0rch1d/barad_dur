require "test_helper"

# Two habits that only show up in the second round: work written before
# implementation landing off-branch, and a reviewer being handed its own
# previous findings to re-confirm.
class BranchAndRoutingTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    File.write(File.join(@repo, "README.md"), "x\n")
    git("add", "-A")
    git("commit", "-qm", "base")
    @ticket = Ticket.create!(code: "TST-BR2", title: "t", repo: "sample-repo", state: :investigation)
  end

  teardown { FileUtils.remove_entry(@repo) }

  def git(*args) = Open3.capture2e("git", "-C", @repo, *args)
  def head = git("rev-parse", "--abbrev-ref", "HEAD").first.strip

  def prepare(phase)
    run = @ticket.phase_runs.create!(phase: phase, status: "running", started_at: Time.current)
    ClaudeCodeRunner.new(@ticket, run).send(:prepare_branch, @repo)
  end

  test "investigation already works on the ticket's branch" do
    prepare("investigation")

    assert_equal "pipe/tst-br2", head,
                 "the record and contract are written here and belong with the work"
  end

  test "planning does not inherit whatever branch the shared checkout was left on" do
    git("checkout", "-q", "-b", "pipe/someone-else")

    prepare("planning")

    assert_equal "pipe/tst-br2", head
  end

  test "a later phase checks the branch out again rather than resetting it" do
    prepare("investigation")
    File.write(File.join(@repo, "work.rb"), "real work\n")
    git("add", "-A")
    git("commit", "-qm", "implementation commit")
    git("checkout", "-q", "main")

    prepare("testing")

    assert_equal "pipe/tst-br2", head
    assert_match(/implementation commit/, git("log", "--oneline").first,
                 "checkout -B here would have discarded it")
  end

  # ── feedback routing ──────────────────────────────────────────────────
  test "review is never handed the previous round's feedback" do
    @ticket.update!(feedback: "the cache key ignores the venue")

    review = PhasePrompts.build(@ticket, "review")

    refute_includes review, "the cache key ignores the venue",
                    "a re-run anchored to its own findings confirms them instead of re-deriving them"
  end

  test "the implementer and the tester both get it" do
    @ticket.update!(feedback: "the cache key ignores the venue")

    %w[implementation testing].each do |phase|
      prompt = PhasePrompts.build(@ticket, phase)
      assert_includes prompt, "the cache key ignores the venue", "#{phase} needs it"
      assert_match(/address this feedback first/i, prompt)
    end
  end

  test "criteria reach the board index without being clipped mid-clause" do
    long = "GIVEN a retry sequence that has used all three attempts " * 4
    ClaudeCodeRunner.apply_enrichment(@ticket, { "acceptance_criteria" => [long] * 12 })

    assert_equal 12, @ticket.reload.acceptance_criteria.size
    assert_operator @ticket.acceptance_criteria.first.length, :>, 200
  end

  test "a risky ticket says so on the verdict card, whatever the landing mode" do
    @ticket.update!(risky: true)

    assert_match(/flagged risky/i, PipelineText.verdict_reason(@ticket))
  end

  test "every phase has delegate hints, so none silently offers none" do
    Ticket::PHASES.each do |phase|
      assert Harness::PHASE_AGENT_HINTS.key?(phase), "#{phase} has no hints at all"
    end
  end
end
