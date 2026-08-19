require "test_helper"

# The phase boundary belongs to Ruby. Everything a phase needs to start is
# computed here and handed over as fact — including, and especially, the fact
# that something upstream is missing.
class PhaseBriefTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "Test")
    File.write(File.join(@repo, "Gemfile"), "source 'x'\n")
    FileUtils.mkdir_p(File.join(@repo, "spec"))
    File.write(File.join(@repo, "spec/a_spec.rb"), "describe 'x'\n")
    File.write(File.join(@repo, "CLAUDE.md"), "Always use keyword arguments.\n")
    git("add", "-A")
    git("commit", "-qm", "base")

    @ticket = Ticket.create!(code: "TST-BR", title: "Cache metadata", repo: "sample-repo",
                             state: :planning, description: "Backtests refetch metadata.",
                             acceptance_criteria: ["Repeat runs hit the cache"])
  end

  teardown { FileUtils.remove_entry(@repo) }

  def git(*args) = Open3.capture2e("git", "-C", @repo, *args)
  def brief(phase = "planning") = PhaseBrief.payload(@ticket, phase, @repo)

  test "the base commit is resolved, not left for the agent to guess" do
    data = brief

    assert_equal "main", data["base_branch"]
    assert_match(/\A[0-9a-f]{40}\z/, data["base_sha"])
  end

  test "the toolchain is discovered, and says whether each command can actually run" do
    entry = brief["toolchain"].find { |c| c["kind"] == "unit" }

    assert_equal "bundle exec rspec", entry["command"]
    assert_includes entry.keys, "runnable"
    assert_includes entry["because"], "Gemfile"
  end

  test "the repo's own conventions are inlined, since they never auto-load in the harness" do
    conventions = brief["repo_conventions"]

    assert_equal ["CLAUDE.md"], conventions.map { |c| c["path"] }
    assert_includes conventions.first["text"], "keyword arguments"
  end

  test "answered questions travel as decisions; unanswered ones do not travel at all" do
    Question.create!(ticket_code: "TST-BR", phase: "investigation", asked_at: 1.hour.ago,
                     body: "Memory or disk?", options: %w[Memory Disk], chosen: "Disk",
                     status: "answered")
    Question.create!(ticket_code: "TST-BR", phase: "investigation", asked_at: 1.minute.ago,
                     body: "Still open?", options: %w[A B])

    decisions = brief["answered_questions"]

    assert_equal 1, decisions.size
    assert_equal "Disk", decisions.first["chosen"]
  end

  test "a missing upstream section is named rather than left to be discovered" do
    assert_equal %w[intent], brief("planning")["degraded"]

    PhaseRecord.ensure!(@repo, "TST-BR")
    File.write(PhaseRecord.path(@repo, "TST-BR"), "## Intent\n\nCache it.\n\n## Findings\n\nx\n")

    assert_empty brief("planning")["degraded"]
  end

  test "the contract's criteria win over the ticket's, because the ticket column truncates" do
    PhaseRecord.ensure!(@repo, "TST-BR")
    File.write(PhaseRecord.contract_path(@repo, "TST-BR"),
               JSON.generate(criteria: [{ id: 1, text: "A" * 400 }]))

    assert_equal 400, brief["acceptance_criteria"].first.length
  end

  test "the brief is written to a path the prompt can name, and gitignored" do
    path = PhaseBrief.write!(@ticket, "planning", @repo)

    assert_equal path, PhaseBrief.path(@repo, "TST-BR")
    assert JSON.parse(File.read(path))["_v"]
    assert_includes File.read(File.join(@repo, ".pipe/.gitignore")), "*.brief.json"
  end

  test "writing the brief creates the record with all seven headings and never overwrites it" do
    PhaseBrief.write!(@ticket, "investigation", @repo)
    File.write(PhaseRecord.path(@repo, "TST-BR"), "## Intent\n\nmine\n")

    PhaseBrief.write!(@ticket, "planning", @repo)

    assert_equal "## Intent\n\nmine\n", File.read(PhaseRecord.path(@repo, "TST-BR"))
  end

  test "a repository that does not exist does not take the run down" do
    assert_nil PhaseBrief.write!(@ticket, "planning", nil)
  end
end

class PhaseRecordTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    PhaseRecord.ensure!(@repo, "TST-RC")
  end

  teardown { FileUtils.remove_entry(@repo) }

  def write(body) = File.write(PhaseRecord.path(@repo, "TST-RC"), body)

  test "a heading with no content under it counts as missing, not as present" do
    write("## Intent\n\n## Findings\n\nreal content\n")

    assert_equal %w[Findings], PhaseRecord.sections(@repo, "TST-RC").keys
  end

  test "each phase is told only about the sections it actually needs" do
    write("## Intent\n\nCache it.\n")

    assert_empty PhaseRecord.degraded(@repo, "TST-RC", "planning")
    assert_equal %w[plan], PhaseRecord.degraded(@repo, "TST-RC", "implementation")
    assert_equal %w[changes], PhaseRecord.degraded(@repo, "TST-RC", "testing")
  end

  test "planning and implementation refuse a hole; the others report it and carry on" do
    assert PhaseRecord.blocking?("planning", %w[intent])
    assert PhaseRecord.blocking?("implementation", %w[plan])
    refute PhaseRecord.blocking?("review", %w[intent])
    refute PhaseRecord.blocking?("testing", %w[changes])
    refute PhaseRecord.blocking?("planning", [])
  end

  test "a heading that is not one of the seven is ignored rather than parsed as a section" do
    write("## Intent\n\nreal\n\n## Notes\n\nsomeone improvised\n")

    assert_equal %w[Intent], PhaseRecord.sections(@repo, "TST-RC").keys
  end

  test "a phase that ran and wrote nothing blocks the phase that needed it" do
    ticket = Ticket.create!(code: "TST-RC", title: "t", repo: "sample-repo", state: :implementation)
    ticket.phase_runs.create!(phase: "investigation", status: "done", started_at: 2.hours.ago)
    ticket.phase_runs.create!(phase: "planning", status: "done", started_at: 1.hour.ago)
    run = ticket.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)

    refute ClaudeCodeRunner.new(ticket, run).send(:prerequisites_met?, @repo)

    assert_equal "failed", run.reload.status
    assert_match(/intent and plan/, run.note)
    assert_match(/investigation and planning/, run.note, "say which phase has to be re-run")
  end

  test "a phase that never ran leaves a gap to work around, not a dead end" do
    ticket = Ticket.create!(code: "TST-RC", title: "t", repo: "sample-repo", state: :implementation)
    run = ticket.phase_runs.create!(phase: "implementation", status: "running", started_at: Time.current)

    assert ClaudeCodeRunner.new(ticket, run).send(:prerequisites_met?, @repo),
           "a realm with investigation switched off must not dead-end every ticket"
    assert_equal "running", run.reload.status
  end
end
