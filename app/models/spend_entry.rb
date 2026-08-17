# One row per charge. Every total in the app is a query over this table, so
# "today", "per agent" and "per ticket" can never drift apart the way three
# separate counters did.
class SpendEntry < ApplicationRecord
  belongs_to :agent, optional: true

  SOURCES = %w[phase chat rfc archive enrich legacy].freeze

  scope :today, -> { where(occurred_at: Time.current.all_day) }
  scope :since, ->(time) { where(occurred_at: time..) }

  # The only way spend is recorded. Inserting (rather than incrementing a
  # counter) is atomic, so concurrent runs in the web and ticker processes
  # cannot lose each other's charges.
  def self.record!(amount, source:, ticket: nil, agent: nil, phase: nil, llm_model: nil, at: Time.current)
    amount = amount.to_f.round(4)
    return nil unless amount.positive?

    entry = create!(amount: amount, source: source.to_s, phase: phase,
                    ticket_code: ticket&.code, agent: agent, llm_model: llm_model,
                    occurred_at: at)
    # tickets.cost is a cache for the board and drawer; increment! is atomic
    ticket&.increment!(:cost, amount)
    entry
  end

  def self.total_today = today.sum(:amount)

  # Contiguous hourly totals ending at the current hour — including the hours
  # nothing was spent, so the bars represent time rather than just the hours
  # that happen to have rows.
  def self.hourly_bars(hours = 14, now: Time.current)
    last_bucket = now.beginning_of_hour
    first_bucket = last_bucket - (hours - 1).hours
    totals = since(first_bucket).group_by { |e| e.occurred_at.beginning_of_hour }
                                .transform_values { |rows| rows.sum(&:amount) }
    (0...hours).map do |i|
      bucket = first_bucket + i.hours
      Bar.new(bucket, totals[bucket] || 0)
    end
  end

  Bar = Struct.new(:bucket, :amount)
end
