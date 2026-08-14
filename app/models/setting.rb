class Setting < ApplicationRecord
  AUTONOMY_MODES = %w[auto risky every].freeze

  validates :autonomy, inclusion: { in: AUTONOMY_MODES }

  def self.instance
    first_or_create!
  end

  # Wizard auth choice: "0" = Claude subscription (default), "1" = API key.
  def auth_mode
    setup.fetch("auth", "0") == "1" ? "api_key" : "subscription"
  end

  def subscription_auth?
    auth_mode == "subscription"
  end

  def spend_pct
    return 0 if spend_cap.zero?
    ((spend_today / spend_cap) * 100).round
  end
end
