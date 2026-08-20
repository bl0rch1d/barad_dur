require "test_helper"

# The framework step used to offer "vanilla", which silently turned six phases
# into three-line prompts, and it said only whether a harness staffed a phase —
# never which one, so a half-mapped harness looked the same as a whole one.
class WizardHarnessStepTest < ActionDispatch::IntegrationTest
  setup do
    @setting = Setting.instance
    @setting.update!(setup: {})
  end

  def step3 = get(root_path(wizard: 3))

  test "the framework step no longer offers a way to turn the harness off wholesale" do
    step3

    assert_response :success
    refute_includes response.body, "Vanilla",
                    "opting out is per phase now; a global switch just hides six short prompts"
  end

  test "each phase row names the harness that staffs it, not merely that one does" do
    step3

    # Whichever harness the workspace happens to carry, every phase resolves to
    # something and the row says which source it came from.
    Ticket::PHASES.each do |phase|
      invocation, source = Harness.source_for(phase)
      assert invocation, "#{phase} resolved to nothing at all"
      assert_includes response.body, invocation, "#{phase}'s command is not shown"
      label = source.bundled? ? "shipped" : source.repo.truncate(14)
      assert_includes response.body, label, "#{phase} does not say which harness staffs it"
    end
  end

  test "the header admits when two harnesses are sharing the work" do
    filled = Ticket::PHASES.count { |phase| Harness.source_for(phase).last&.bundled? }
    skip "this workspace's harness covers every phase" if filled.zero? || Harness.detect.bundled?

    step3

    assert_match(/filling #{filled} phase/, response.body,
                 "naming only the primary harness hides that another is doing part of the work")
  end

  test "a workspace harness that stops short shows the shipped one filling the rest" do
    filled = Ticket::PHASES.filter_map { |phase| Harness.source_for(phase).last }

    skip "this workspace's harness covers every phase" if filled.none?(&:bundled?)

    step3
    assert_includes response.body, "shipped",
                    "a half-mapped harness must be visible rather than mysterious"
  end

  test "a phase switched to its built-in prompt says that is a choice, not an absence" do
    @setting.update!(setup: @setting.setup.merge("map:review" => "built-in"))

    step3

    assert_includes response.body, "you switched this off"
  end

  test "a harness directory that resolves to nothing fails loudly" do
    @setting.update!(setup: @setting.setup.merge("harness_dir" => "not-a-real-place"))

    step3

    assert_includes response.body, "is not a harness"
    assert_includes response.body, "almost certainly not what you picked it for"
  end

  test "choosing the bundled harness deliberately is not reported as an error" do
    @setting.update!(setup: @setting.setup.merge("harness_dir" => Harness::BUNDLED_CHOICE))

    step3

    refute_includes response.body, "is not a harness"
  end

  test "every wizard step still renders with the reworked framework card" do
    (1..5).each do |step|
      get root_path(wizard: step)
      assert_response :success, "step #{step} broke"
    end
  end
end
