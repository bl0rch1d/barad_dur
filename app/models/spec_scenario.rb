class SpecScenario < ApplicationRecord
  belongs_to :spec_requirement

  validates :name, presence: true
end
