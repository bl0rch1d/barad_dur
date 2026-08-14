class Agent < ApplicationRecord
  STATUSES = %w[idle running waiting].freeze

  has_many :tickets

  validates :name, :abbr, :role, :llm_model, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position) }
  scope :idle, -> { where(status: "idle") }

  def tone
    case status
    when "running" then "var(--accent)"
    when "waiting" then "var(--warn)"
    else "var(--tx3)"
    end
  end

  def soft
    case status
    when "running" then "var(--accent-soft)"
    when "waiting" then "var(--warn-soft)"
    else "var(--sunken)"
    end
  end
end
