class SpecRequirement < ApplicationRecord
  belongs_to :capability
  has_many :spec_scenarios, -> { order(:position) }, dependent: :destroy

  validates :rid, :name, presence: true

  def tone
    case status
    when "implemented" then "var(--ok)"
    when "in review"   then "var(--warn)"
    else "var(--tx3)"
    end
  end
end
