require "test_helper"

# The cap was displayed in the wizard but only changeable after setup, which
# is backwards: it is the one number worth deciding before agents can spend.
class WizardSpendCapTest < ActionDispatch::IntegrationTest
  test "the auth step offers the cap as a choice, marking the current one" do
    Setting.instance.update!(spend_cap: 80)

    get root_path(wizard: 2)

    assert_response :success
    assert_includes response.body, "Daily spend cap"
    assert_match(/class="chip on"[^>]*>\s*\$80/m, response.body, "the current cap is marked")
    %w[10 25 50 150 300].each do |cap|
      assert_includes response.body, "$#{cap}", "the $#{cap} option should be offered"
    end
  end

  test "choosing a cap saves it" do
    Setting.instance.update!(spend_cap: 80)

    post wizard_patch_path(key: "spend_cap", value: 25, wizard: 2)

    assert_equal 25, Setting.instance.reload.spend_cap.to_i
  end

  test "a nonsensical cap is refused rather than stored" do
    Setting.instance.update!(spend_cap: 80)

    post wizard_patch_path(key: "spend_cap", value: 0, wizard: 2)
    assert_equal 80, Setting.instance.reload.spend_cap.to_i, "zero would mean nothing ever runs"

    post wizard_patch_path(key: "spend_cap", value: 999_999, wizard: 2)
    assert_equal 80, Setting.instance.reload.spend_cap.to_i

    post wizard_patch_path(key: "spend_cap", value: "; DROP TABLE", wizard: 2)
    assert_equal 80, Setting.instance.reload.spend_cap.to_i
  end
end
