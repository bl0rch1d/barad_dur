require "test_helper"

# "Make the tests pass" is the instruction under which deleting the failing test
# is the shortest path. The tester is told not to; nothing checked.
class TestGuardTest < ActiveSupport::TestCase
  setup do
    @repo = Dir.mktmpdir
    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "Test")
    write("spec/order_spec.rb", <<~RB)
      describe Order do
        it "totals" do
          expect(order.total).to eq(10)
          expect(order.tax).to eq(1)
          expect(order.net).to eq(9)
          expect(order.currency).to eq("USD")
        end
      end
    RB
    write("app/order.rb", "class Order; end\n")
    git("add", "-A")
    git("commit", "-qm", "baseline")
    git("checkout", "-q", "-b", "pipe/tst-1")
  end

  teardown { FileUtils.remove_entry(@repo) }

  def git(*args)
    Open3.capture2e("git", "-C", @repo, *args)
  end

  def write(path, body)
    full = File.join(@repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def commit(message)
    git("add", "-A")
    git("commit", "-qm", message)
  end

  def flags = TestGuard.inspect_branch(@repo, "main")

  test "a branch that leaves the suite alone raises nothing" do
    write("app/order.rb", "class Order; def total = 10; end\n")
    commit("implement")

    assert_empty flags
  end

  test "deleting a test file is reported" do
    FileUtils.rm(File.join(@repo, "spec/order_spec.rb"))
    commit("remove the failing spec")

    flag = flags.find { |f| f["kind"] == "deleted" }
    assert_equal "spec/order_spec.rb", flag["path"]
  end

  test "deleting production code is not a suite problem" do
    FileUtils.rm(File.join(@repo, "app/order.rb"))
    commit("remove the class")

    assert_empty flags.select { |f| f["kind"] == "deleted" }
  end

  test "a skip added to a test is reported with the line that added it" do
    write("spec/order_spec.rb", <<~RB)
      describe Order do
        it "totals" do
          skip("flaky on CI")
          expect(order.total).to eq(10)
          expect(order.tax).to eq(1)
          expect(order.net).to eq(9)
          expect(order.currency).to eq("USD")
        end
      end
    RB
    commit("skip it")

    flag = flags.find { |f| f["kind"] == "skipped" }
    assert_equal "spec/order_spec.rb", flag["path"]
    assert_match(/skip/, flag["line"])
  end

  test "gutting a test's assertions is reported even when the file survives" do
    write("spec/order_spec.rb", <<~RB)
      describe Order do
        it "totals" do
          expect(order.total).to eq(10)
        end
      end
    RB
    commit("simplify")

    flag = flags.find { |f| f["kind"] == "assertions" }
    assert_equal "spec/order_spec.rb", flag["path"]
    assert_match(/removed/, flag["detail"])
  end

  test "moving one assertion around is not gutting it" do
    write("spec/order_spec.rb", <<~RB)
      describe Order do
        it "totals" do
          expect(order.total).to eq(10)
          expect(order.tax).to eq(1)
          expect(order.net).to eq(9)
        end
      end
    RB
    commit("drop one")

    assert_empty flags.select { |f| f["kind"] == "assertions" },
                 "a refactor moves assertions; the guard must not cry wolf"
  end

  test "pytest, jest and go conventions are recognised too" do
    %w[tests/test_orders.py __tests__/orders.test.js pkg/orders_test.go].each do |path|
      assert TestGuard.test_path?(path), "#{path} should count as a test"
    end
    refute TestGuard.test_path?("app/services/latest_order.rb")
  end

  test "a weakened suite makes the pull request stop looking green" do
    ticket = Ticket.create!(code: "TST-G1", title: "g", repo: "sample-repo", state: :testing)
    ticket.phase_runs.create!(phase: "testing", status: "done", started_at: Time.current,
                              tests_executed: true, tests_passed: 12, tests_failed: 0,
                              guard_flags: [{ "kind" => "deleted", "path" => "spec/x_spec.rb",
                                              "detail" => "test file deleted" }])

    assert ticket.tests_weakened?
    assert ticket.verification_red?, "12 passing tests mean nothing if the failing one was deleted"
    assert_equal "[suite weakened] ", PushPrJob.new.send(:pr_prefix, ticket)
  end

  test "the pull request body carries the verification story, bad news included" do
    ticket = Ticket.create!(code: "TST-G2", title: "g", repo: "sample-repo", state: :testing)
    ticket.phase_runs.create!(phase: "testing", status: "done", started_at: Time.current,
                              tests_executed: true, tests_passed: 12, tests_failed: 1,
                              tests_command: "bundle exec rspec",
                              test_suites: [{ "kind" => "e2e", "skipped" => "needs a server" }],
                              guard_flags: [{ "kind" => "skipped", "path" => "spec/x_spec.rb",
                                              "detail" => "skip/pending" }])

    body = PushPrJob.new.send(:pr_body, ticket)

    assert_match(/12 passed, 1 failed/, body)
    assert_match(/e2e: not run — needs a server/, body)
    assert_match(/WARNING/, body)
    assert_match(%r{spec/x_spec\.rb}, body)
  end

  test "a ticket that ran no suite says so in the body rather than staying silent" do
    ticket = Ticket.create!(code: "TST-G3", title: "g", repo: "sample-repo", state: :testing)

    assert_match(/nothing here has been verified/i, PushPrJob.new.send(:pr_body, ticket))
  end
end
