class Ticket < ApplicationRecord
  # NOTE: the first state is named :backlog (displayed as "Not ready") because
  # an enum value literally named :not_ready collides with the `not_ready`
  # negation scope Rails auto-generates for the :ready value.
  STATES = {
    backlog: 0, ready: 1,
    investigation: 2, planning: 3, implementation: 4,
    review: 5, testing: 6, deployment: 7, done: 8
  }.freeze
  PHASES = %w[investigation planning implementation review testing deployment].freeze

  # Ticks a ticket spends in each phase before the engine attempts a transition.
  PHASE_THRESHOLDS = {
    "investigation" => 4, "planning" => 3, "implementation" => 7,
    "review" => 3, "testing" => 4, "deployment" => 2
  }.freeze

  enum :state, STATES

  belongs_to :agent, optional: true
  has_many :phase_runs, dependent: :destroy
  has_many :ticket_gates, class_name: "Gate", dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :title, presence: true

  scope :on_board, -> { where.not(state: :done) }
  scope :in_flight, -> { where(state: PHASES) }

  def phase
    PHASES.include?(state) ? state : nil
  end

  def phase_index
    PHASES.index(state)
  end

  def next_state
    idx = STATES[state.to_sym]
    STATES.key(idx + 1)&.to_s
  end

  def gated?
    ticket_gates.pending.exists?
  end

  def blocked_by_question?
    Question.pending.exists?(ticket_code: code)
  end

  def current_phase_run
    phase_runs.where(phase: state).order(:started_at).last
  end

  # A live (claude code) run owns this ticket's progression — the demo
  # tick-threshold driver must leave it alone.
  def live_run?
    current_phase_run&.runner == "claude"
  end

  def agent_label
    agent&.name || (ready? ? "queued" : "unassigned")
  end
end
