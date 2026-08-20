require "test_helper"

# The CLI refuses --dangerously-skip-permissions under root and exits 1 with
# no output, so every phase fails as "exited with status 1 without a result" —
# a message that says nothing about the cause. The dev image runs as root.
class SandboxEnvTest < ActiveSupport::TestCase
  def sandbox(env) = HeadlessAgent.send(:sandbox_env, env)

  test "running as root, the CLI is told it is in a sandbox" do
    skip "not running as root here" unless Process.uid.zero?

    assert_equal "1", sandbox({})["IS_SANDBOX"]
  end

  test "it does not disturb the rest of the environment" do
    result = sandbox({ "ANTHROPIC_API_KEY" => nil, "FOO" => "bar" })

    assert_nil result["ANTHROPIC_API_KEY"], "the credential nulling must survive"
    assert_equal "bar", result["FOO"]
  end

  test "an explicit setting is left alone" do
    ENV["IS_SANDBOX"] = "0"

    refute_includes sandbox({}).keys, "IS_SANDBOX",
                    "someone who set this deliberately has decided already"
  ensure
    ENV.delete("IS_SANDBOX")
  end

  test "the flags the CLI is given are still the permission-bypassing ones" do
    assert_match(/bypassPermissions/, ClaudeCodeRunner::DEFAULT_FLAGS,
                 "if this changes, the root refusal no longer applies and this can go")
  end
end
