class Release < ApplicationRecord
  validates :version, presence: true

  scope :ordered, -> { order(:position) }

  def tone
    kind == "shipped" ? "var(--ok)" : "var(--warn)"
  end

  def self.staged
    where(kind: "staged").order(:position).last
  end
end
