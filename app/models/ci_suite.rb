class CiSuite < ApplicationRecord
  validates :name, presence: true

  scope :ordered, -> { order(:position) }

  def tone
    pct >= 95 ? "var(--ok)" : "var(--warn)"
  end
end
