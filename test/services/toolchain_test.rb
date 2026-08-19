require "test_helper"

# The testing phase rediscovered how to run each project on every run, which
# costs turns on an answer that never changes — and when the turns ran short it
# finished having verified nothing at all.
class ToolchainTest < ActiveSupport::TestCase
  setup { @repo = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@repo) }

  def write(path, body = "")
    full = File.join(@repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def commands = Toolchain.detect(@repo).map(&:command)

  test "a rails project with rspec and rubocop" do
    write("Gemfile", "source 'https://rubygems.org'\n")
    write("Gemfile.lock", "    rubocop (1.60.0)\n")
    write("spec/models/order_spec.rb")
    write("bin/rails")

    assert_includes commands, "bundle exec rspec"
    assert_includes commands, "bundle exec rubocop"
  end

  test "a rails project on minitest uses its own runner, not rspec" do
    write("Gemfile", "source 'x'\n")
    write("test/models/order_test.rb")
    write("bin/rails")

    assert_includes commands, "bin/rails test"
    refute_includes commands, "bundle exec rspec"
  end

  test "node scripts are read rather than guessed, with the right package manager" do
    write("package.json", JSON.generate(scripts: { "test" => "vitest", "lint" => "eslint .",
                                                   "e2e" => "playwright test" }))
    write("pnpm-lock.yaml")

    assert_includes commands, "pnpm test"
    assert_includes commands, "pnpm lint"
    assert_includes commands, "pnpm e2e"
  end

  test "a package.json with no useful scripts contributes nothing" do
    write("package.json", JSON.generate(scripts: { "build" => "vite build" }))

    assert_empty commands
  end

  test "malformed package.json does not take the phase down with it" do
    write("package.json", "{ not json")

    assert_empty commands
  end

  test "python, go and rust are recognised" do
    write("pyproject.toml", "[tool.ruff]\n[tool.pytest.ini_options]\n")
    assert_includes commands, "pytest"
    assert_includes commands, "ruff check ."

    FileUtils.remove_entry(@repo)
    @repo = Dir.mktmpdir
    write("go.mod", "module x\n")
    write(".golangci.yml")
    assert_includes commands, "go test ./..."
    assert_includes commands, "golangci-lint run"

    FileUtils.remove_entry(@repo)
    @repo = Dir.mktmpdir
    write("Cargo.toml", "[package]\n")
    assert_includes commands, "cargo test"
  end

  test "a Makefile target beats a guess, because someone wrote it on purpose" do
    write("Makefile", "lint:\n\truff check .\n\ntest:\n\tpytest -q\n\nbuild:\n\techo no\n")

    assert_includes commands, "make lint"
    assert_includes commands, "make test"
    refute_includes commands, "make build"
  end

  test "commands come back in the order they should be run" do
    write("Gemfile", "x")
    write("Gemfile.lock", "rubocop (1.0)")
    write("spec/a_spec.rb")
    write("test/system/a_test.rb")

    assert_equal %w[lint unit e2e], Toolchain.detect(@repo).map(&:kind)
  end

  test "a repository it cannot read produces no claims about it" do
    assert_empty Toolchain.detect(@repo), "an empty directory has no suites"
    assert_empty Toolchain.detect("/nonexistent-path")
    assert_nil Toolchain.describe(@repo)
  end

  test "the description tells the agent the list is a starting point, not gospel" do
    write("go.mod", "module x\n")

    description = Toolchain.describe(@repo)

    assert_includes description, "go test ./..."
    assert_match(/read off the repository's own configuration/i, description)
    assert_match(/correct it where it is wrong/i, description)
  end

  test "the testing prompt carries the toolchain, and the other phases do not" do
    write("Gemfile", "x")
    write("spec/a_spec.rb")
    ticket = Ticket.create!(code: "TST-T1", title: "t", repo: "sample-repo", state: :testing)

    testing = PhasePrompts.execution(ticket, "testing", @repo)[:prompt]
    implementation = PhasePrompts.execution(ticket, "implementation", @repo)[:prompt]

    assert_includes testing, "bundle exec rspec"
    refute_includes implementation, "bundle exec rspec"
  end

  test "a suite the repo has but the run never mentioned is called out" do
    write("Gemfile", "x")
    write("Gemfile.lock", "rubocop (1.0)")
    write("spec/a_spec.rb")
    ticket = Ticket.create!(code: "TST-T2", title: "t", repo: "sample-repo", state: :testing)
    run = ticket.phase_runs.create!(phase: "testing", status: "running", started_at: Time.current)
    runner = ClaudeCodeRunner.new(ticket, run)
    runner.instance_variable_set(:@repo, @repo)

    runner.send(:report_unrun_suites, [{ "kind" => "unit", "passed" => 9 }])

    event = Event.where(meta: "not reported").last
    assert_match(/lint/, event.text)
    refute_match(/unit/, event.text, "it ran the unit suite and said so")
  end

  test "a run that accounted for everything is not nagged" do
    write("go.mod", "module x\n")
    ticket = Ticket.create!(code: "TST-T3", title: "t", repo: "sample-repo", state: :testing)
    run = ticket.phase_runs.create!(phase: "testing", status: "running", started_at: Time.current)
    runner = ClaudeCodeRunner.new(ticket, run)
    runner.instance_variable_set(:@repo, @repo)

    runner.send(:report_unrun_suites, [{ "kind" => "unit", "passed" => 9 }])

    assert_nil Event.where(meta: "not reported").last
  end
end
