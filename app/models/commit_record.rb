class CommitRecord < ApplicationRecord
  validates :sha, :message, presence: true

  scope :recent, -> { order(committed_at: :desc) }
end
