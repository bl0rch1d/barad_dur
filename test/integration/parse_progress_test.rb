require "test_helper"

# The indexing card used to ease itself to 100% in about ten seconds and
# unlock Continue, whatever the real parse was doing — a 65-file workspace
# takes over a minute, so it announced work that had barely started.
class ParseProgressTest < ActionDispatch::IntegrationTest
  setup { Setting.instance.update!(setup_complete: true) }

  def parsing!(done:, total:, label: "quant_development/kill-switch", at: Time.current)
    setting = Setting.instance
    setting.update!(setup: setting.setup.merge(
      "spec_sync_progress" => { "done" => done, "total" => total, "label" => label, "at" => at.to_i }
    ))
  end

  test "while a parse runs the card shows its real position and stays incomplete" do
    parsing!(done: 3, total: 65)

    get root_path(wizard: 4)

    assert_includes response.body, 'data-progress-busy-value="true"'
    assert_includes response.body, 'data-progress-pct-value="4"', "3 of 65 is 4%, not 100%"
    assert_includes response.body, "Parsing specs — 3 of 65"
    assert_match(/id="wizard-continue"[^>]*class="btn-accent locked"/, response.body,
                 "Continue must stay locked until the parse really finishes")
  end

  test "the live row names the file being parsed rather than a finished count" do
    parsing!(done: 12, total: 65, label: "quant_web/strategy-queue")

    get root_path(wizard: 4)

    assert_includes response.body, "parsing quant_web/strategy-queue — 12 of 65"
  end

  test "once the parse finishes the card is free to complete" do
    Capability.create!(slug: "r/one", file: "f", title: "One", purpose: "p", position: 0)

    get root_path(wizard: 4)

    assert_includes response.body, 'data-progress-busy-value="false"'
    assert_includes response.body, "Indexing workspace"
    assert_includes response.body, "parsed 1 openspec capabilities"
  end

  test "a stale marker does not pin the card as busy forever" do
    parsing!(done: 3, total: 65, at: 5.minutes.ago)

    get root_path(wizard: 4)

    assert_includes response.body, 'data-progress-busy-value="false"',
                    "a marker left by a dead job must not lock the wizard"
  end
end
