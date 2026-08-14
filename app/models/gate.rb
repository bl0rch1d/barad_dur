class Gate < ApplicationRecord
  belongs_to :ticket

  scope :pending, -> { where(status: "pending") }

  def to_state_name
    Ticket::STATES.key(to_state).to_s
  end
end
