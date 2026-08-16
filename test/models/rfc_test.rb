require "test_helper"

class RfcTest < ActiveSupport::TestCase
  PROPOSALS = [
    { "step" => "1", "title" => "Add venue field to OrderIntent", "repo" => "core",
      "dep_indexes" => [], "est" => "40m", "tag" => "schema", "risky" => false,
      "summary" => "Adds the venue axis to intents.",
      "acceptance_criteria" => ["Intents carry a venue"] },
    { "step" => "2", "title" => "Per-venue exposure accumulator", "repo" => "core",
      "dep_indexes" => [1], "est" => "1h 30m", "tag" => "core", "risky" => false },
    { "step" => "3", "title" => "Halt venue on breach", "repo" => "core",
      "dep_indexes" => [2], "est" => "1h 10m", "tag" => "risky", "risky" => true,
      "change" => "venue-exposure-cap" }
  ].freeze

  test "push_to_board files ready-to-implement tickets with codes, deps and briefs" do
    rfc = Rfc.create!(body: "cap venue exposure", stage: 3, proposals: PROPOSALS)

    assert_difference -> { Ticket.count }, +3 do
      rfc.push_to_board!
    end
    assert rfc.reload.pushed?

    codes = Ticket.order(:id).last(3).map(&:code)
    first, second, third = Ticket.order(:id).last(3)
    assert codes.all? { |c| c.match?(/\AALG-\d+\z/) }
    assert_equal "ready_to_implement", first.state
    assert_equal "Adds the venue axis to intents.", first.description
    assert_equal ["Intents carry a venue"], first.acceptance_criteria
    assert_equal [first.code], second.dep_codes
    assert_equal [second.code], third.dep_codes
    assert third.risky?
    assert_includes third.artifacts, "openspec change: venue-exposure-cap"

    # pushing twice does not duplicate
    assert_no_difference -> { Ticket.count } do
      rfc.push_to_board!
    end
  end

  test "reset clears derived state" do
    rfc = Rfc.create!(body: "x", stage: 3, trace: [{ "a" => 1 }], proposals: PROPOSALS,
                      job_state: "failed", error: "boom", progress_note: "note")
    rfc.reset!
    assert_equal 0, rfc.stage
    assert_empty rfc.trace
    assert_empty rfc.proposals
    assert_equal "idle", rfc.job_state
    assert_nil rfc.error
  end
end
