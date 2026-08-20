require "test_helper"

# Planning records, before any code exists, what "done" means and what the test
# suite looked like. Both have to be measured by Ruby rather than asserted by an
# agent — a digest cannot be reported optimistically.
class FrozenContractTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    write("spec/order_spec.rb", "expect(a).to eq(1)\nexpect(b).to eq(2)\n")
    write("app/order.rb", "class Order; end\n")
    git("add", "-A")
    git("commit", "-qm", "base")
    @base = git("rev-parse", "HEAD").first.strip
    @ticket = Ticket.create!(code: "TST-FC", title: "t", repo: "sample-repo", state: :planning,
                             acceptance_criteria: ["Repeat runs hit the cache"])
  end

  teardown { FileUtils.remove_entry(@repo) }

  def git(*args) = Open3.capture2e("git", "-C", @repo, *args)

  def write(path, body)
    full = File.join(@repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def freeze!(**over)
    PhaseRecord.freeze!(@repo, "TST-FC", criteria: ["Repeat runs hit the cache"],
                        base_sha: @base, **over)
  end

  test "the digests are the ids git already stored, not something recomputed" do
    contract = freeze!

    blob, = git("rev-parse", "#{@base}:spec/order_spec.rb")
    assert_equal blob.strip, contract["frozen_tests"]["spec/order_spec.rb"]
  end

  test "only test files are frozen — production code is meant to change" do
    contract = freeze!

    assert_includes contract["frozen_tests"].keys, "spec/order_spec.rb"
    refute_includes contract["frozen_tests"].keys, "app/order.rb"
  end

  test "criteria are numbered so later phases can report against them by id" do
    contract = freeze!

    assert_equal [{ "id" => 1, "text" => "Repeat runs hit the cache" }], contract["criteria"]
  end

  # ── the tamper check ─────────────────────────────────────────────────
  test "an untouched suite raises nothing" do
    assert_empty TestGuard.tampered(@repo, freeze!)
  end

  test "editing a frozen test is caught even when nothing else looks wrong" do
    contract = freeze!
    write("spec/order_spec.rb", "expect(a).to eq(1)\nexpect(b).to eq(2)\n# tweak\n")

    flag = TestGuard.tampered(@repo, contract).first

    assert_equal "frozen", flag["kind"]
    assert_match(/modified/, flag["detail"])
  end

  test "deleting a frozen test is caught, and named as a deletion" do
    contract = freeze!
    FileUtils.rm(File.join(@repo, "spec/order_spec.rb"))

    flag = TestGuard.tampered(@repo, contract).first

    assert_match(/deleted/, flag["detail"])
  end

  test "a ticket with no contract is not accused of tampering with it" do
    assert_empty TestGuard.tampered(@repo, nil)
    assert_empty TestGuard.tampered(@repo, {})
  end

  # ── the run-level wiring ─────────────────────────────────────────────
  def runner(phase)
    run = @ticket.phase_runs.create!(phase: phase, status: "running", started_at: Time.current)
    [ClaudeCodeRunner.new(@ticket, run), run]
  end

  test "touching a frozen test stops the ticket for a person" do
    contract = freeze!
    File.write(PhaseRecord.contract_path(@repo, "TST-FC"), JSON.generate(contract))
    write("spec/order_spec.rb", "expect(a).to eq(1)\n")
    r, run = runner("testing")

    r.send(:guard_tests, @repo)

    assert run.reload.guard_flags.any? { |f| f["kind"] == "frozen" }
    assert @ticket.reload.gated?, "this is not a judgement the pipeline can make on its own"
    assert_match(/frozen before the work began/, run.guard_flags.first["detail"])
  end

  test "planning with no criteria anywhere fails the run rather than freezing nothing" do
    @ticket.update!(acceptance_criteria: [])
    r, run = runner("planning")

    refute r.send(:freeze_contract!, @repo)

    assert_equal "failed", run.reload.status
    assert_match(/without a single acceptance criterion/, run.note)
  end

  test "criteria the agent returned are frozen even when it wrote no contract file" do
    r, = runner("planning")

    assert r.send(:freeze_contract!, @repo)

    contract = PhaseRecord.contract(@repo, "TST-FC")
    assert_equal "Repeat runs hit the cache", contract["criteria"].first["text"]
    assert contract["frozen_tests"].any?, "and Ruby measured the digests regardless"
  end
end
