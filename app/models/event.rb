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
    event = create!(
      happened_at: Time.current,
      phase_tag: phase_tag,
      tone: tone || DEFAULT_TONES.fetch(phase_tag, "var(--tx3)"),
      text: text,
      ticket_code: ticket_code || ticket&.code || "—",
      agent_name: agent_name || agent&.name || "system",
      meta: meta,
      cost: cost
    )
    event.broadcast_row
    event
  end

  # Targeted stream: the new event prepends into the dashboard feed without a
  # whole-page morph (pages without #event-feed ignore it).
  def broadcast_row
    Turbo::StreamsChannel.broadcast_prepend_to(
      :app, target: "event-feed", partial: "events/stream_row", locals: { event: self }
    )
  rescue => e
    Rails.logger.debug { "event stream broadcast skipped: #{e.message}" }
  end
end
