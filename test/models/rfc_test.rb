require "test_helper"

class RfcTest < ActiveSupport::TestCase
  test "advances through investigate, clarify and plan stages" do
    rfc = Rfc.create!(body: "Cap per-venue exposure in real time")

    rfc.advance!
    assert_equal 1, rfc.stage
    assert rfc.trace.any?

    rfc.advance!
    assert_equal 2, rfc.stage
    assert_equal 3, rfc.questions.size

    rfc.record_answer!("q1", "Venue only")
    assert_equal "Venue only", rfc.answers["q1"]

    rfc.advance!
    assert_equal 3, rfc.stage
    assert_equal 5, rfc.proposals.size
  end

  test "push_to_board creates ready tickets with dependencies" do
    rfc = Rfc.create!(body: "x", stage: 3, proposals: RfcScript::PROPOSALS)
    assert_difference -> { Ticket.count }, +5 do
      rfc.push_to_board!
    end
    assert rfc.reload.pushed?

    risky = Ticket.find_by(code: "ALG-243")
    assert risky.risky?
    assert_equal "ready_to_implement", risky.state
    assert_equal ["ALG-242"], risky.dep_codes

    # pushing twice does not duplicate
    assert_no_difference -> { Ticket.count } do
      rfc.push_to_board!
    end
  end

  test "reset clears derived state" do
    rfc = Rfc.create!(body: "x", stage: 3, trace: [{ "a" => 1 }], proposals: RfcScript::PROPOSALS)
    rfc.reset!
    assert_equal 0, rfc.stage
    assert_empty rfc.trace
    assert_empty rfc.proposals
  end
end
