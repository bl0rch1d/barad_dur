class ChatMessage < ApplicationRecord
  validates :sender, :body, presence: true

  scope :in_room, ->(room) { where(room: room).order(:sent_at, :id) }

  def from_user?
    sender == "you"
  end
end
