# An openspec capability (a spec document with requirements and scenarios).
# Named Capability rather than Spec because a top-level `Spec` constant makes
# ActiveSupport::Testing::Declarative skip defining the `test` macro.
class Capability < ApplicationRecord
  has_many :spec_requirements, -> { order(:position) }, dependent: :destroy

  validates :slug, :file, :title, presence: true

  scope :ordered, -> { order(:position) }
end
