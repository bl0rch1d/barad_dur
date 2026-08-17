class Setting < ApplicationRecord
  AUTONOMY_MODES = %w[auto risky every].freeze

  validates :autonomy, inclusion: { in: AUTONOMY_MODES }

  def self.instance
    first_or_create!
  end

  ORCHESTRATOR_MODELS = {
    "claude-opus-5"      => "Opus 5",
    "claude-sonnet-5"    => "Sonnet 5",
    "claude-haiku-4-5"   => "Haiku 4.5"
  }.freeze
  DEFAULT_ORCHESTRATOR_MODEL = "claude-opus-5".freeze

  # Model the orchestrator (headless agent runs) uses. Default: Opus 5.
  def orchestrator_model
    model = setup["orchestrator_model"].to_s
    ORCHESTRATOR_MODELS.key?(model) ? model : DEFAULT_ORCHESTRATOR_MODEL
  end

  # Wizard auth choice: "0" = Claude subscription (default), "1" = API key.
  def auth_mode
    setup.fetch("auth", "0") == "1" ? "api_key" : "subscription"
  end

  def subscription_auth?
    auth_mode == "subscription"
  end

  # Derived from the ledger, so it is genuinely "today" and resets itself at
  # midnight without anything having to remember to zero a counter.
  def spend_today
    SpendEntry.total_today
  end

  def spend_pct
    return 0 if spend_cap.zero?
    ((spend_today / spend_cap) * 100).round
  end

  def over_cap?
    return false if setup["cap_override_on"] == Date.current.to_s

    spend_cap.positive? && spend_today >= spend_cap
  end

  # Restarting while over the cap is a decision to keep spending today. The
  # ledger is history and stays intact; the override simply expires tonight.
  def override_cap_for_today!
    update!(setup: setup.merge("cap_override_on" => Date.current.to_s))
  end
end
