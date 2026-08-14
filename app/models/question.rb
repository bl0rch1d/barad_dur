class Question < ApplicationRecord
  scope :pending, -> { where(status: "pending") }

  validates :ticket_code, :body, presence: true

  def answer!(option)
    update!(chosen: option, status: "answered")
  end

  def waited_label
    mins = ((Time.current - asked_at) / 60).round
    mins < 60 ? "#{mins}m" : "#{mins / 60}h #{mins % 60}m"
  end
end
