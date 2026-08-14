class Event < ApplicationRecord
  DEFAULT_TONES = {
    "IMPL"   => "var(--accent)",
    "TEST"   => "var(--warn)",
    "PLAN"   => "var(--info)",
    "REVIEW" => "var(--warn)",
    "INVEST" => "var(--info)",
    "DEPLOY" => "var(--ok)",
    "SPEC"   => "var(--info)",
    "GATE"   => "var(--warn)",
    "SYS"    => "var(--tx3)"
  }.freeze

  validates :phase_tag, :text, presence: true

  scope :recent, -> { order(happened_at: :desc, id: :desc) }

  def self.record!(phase_tag:, text:, tone: nil, ticket: nil, ticket_code: nil,
                   agent: nil, agent_name: nil, meta: nil, cost: 0)
    create!(
      happened_at: Time.current,
      phase_tag: phase_tag,
      tone: tone || DEFAULT_TONES.fetch(phase_tag, "var(--tx3)"),
      text: text,
      ticket_code: ticket_code || ticket&.code || "—",
      agent_name: agent_name || agent&.name || "system",
      meta: meta,
      cost: cost
    )
  end
end
