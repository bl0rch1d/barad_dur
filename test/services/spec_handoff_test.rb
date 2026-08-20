require "test_helper"

# Everything planning produced — the criteria, the notes, and the decisions the
# user made when answering questions — has to reach the phases that come after
# it. Without that each phase re-derives the goal from the code, which is
# grading the change against itself.
class SpecHandoffTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(
      code: "TST-S1", title: "Cache instrument metadata", repo: "sample-repo",
      state: :implementation,
      description: "Backtests refetch the same metadata every run.",
      technical_notes: "Touches backtest/instruments.py — see the CACHE constant.",
      acceptance_criteria: ["Repeat runs hit the cache", "Cache invalidates when the instrument list changes"]
    )
  end

  %w[implementation review testing deployment].each do |phase|
    test "#{phase} is given the acceptance criteria" do
      prompt = PhasePrompts.build(@ticket, phase)

      assert_includes prompt, "Repeat runs hit the cache"
      assert_includes prompt, "Cache invalidates when the instrument list changes"
      assert_match(/before any code/i, prompt, "it must be clear these predate the work")
    end
  end

  test "the planner's notes travel as context, never as the contract" do
    prompt = PhasePrompts.build(@ticket, "review")

    assert_includes prompt, "backtest/instruments.py"
    assert_match(/context, not the contract/i, prompt)
  end

  test "answers the user gave reach every later phase" do
    Question.create!(ticket_code: "TST-S1", phase: "investigation", asked_at: 1.hour.ago,
                     body: "Cache in memory or on disk?", options: %w[Memory Disk],
                     chosen: "Disk", status: "answered")
    Question.create!(ticket_code: "TST-S1", phase: "investigation", asked_at: 30.minutes.ago,
                     body: "Still open?", options: %w[A B])

    prompt = PhasePrompts.build(@ticket, "implementation")

    assert_includes prompt, "Cache in memory or on disk?"
    assert_includes prompt, "Disk", "the decision the user actually made"
    assert_match(/settled/i, prompt, "and it must be framed as binding")
    refute_includes prompt, "Still open?", "an unanswered question is not a decision"
  end

  test "feedback goes to whoever acts on it, and never back to the critic" do
    @ticket.update!(feedback: "the cache key ignores the venue")

    review = PhasePrompts.build(@ticket, "review")
    implementation = PhasePrompts.build(@ticket, "implementation")

    assert_match(/address this feedback first/i, implementation)
    refute_includes review, "the cache key ignores the venue",
                    "a re-run handed its own prior findings is anchored to confirm them, " \
                    "and re-deriving them is the whole value of the second pass"
  end

  test "a harness phase is told where the code actually is" do
    prompt = PhasePrompts.harness_prompt(@ticket, "review", "/review", Setting.instance, "/workspace/quant_web")

    assert_includes prompt, "/workspace/quant_web"
    assert_match(/-C \/workspace\/quant_web/, prompt, "bare git would hit the harness repo instead")
  end

  test "a ticket with no plan yet degrades quietly rather than inventing one" do
    bare = Ticket.create!(code: "TST-S2", title: "Hand-filed", repo: "sample-repo", state: :implementation)

    prompt = PhasePrompts.build(bare, "implementation")

    refute_includes prompt, "Acceptance criteria"
    assert_includes prompt, "Hand-filed"
  end
end
