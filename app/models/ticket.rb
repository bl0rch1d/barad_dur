class Ticket < ApplicationRecord
  # draft        — free-form drafts the user files manually
  # ready        — queued for grooming (investigation → planning)
  # ready_to_implement — groomed or RFC-planned; awaiting an agent + deps
  # (an enum value named :not_ready would collide with the auto-generated
  #  `not_ready` negation scope of :ready — hence :draft)
  STATES = {
    draft: 0, ready: 1,
    investigation: 2, planning: 3, ready_to_implement: 4,
    implementation: 5, review: 6, testing: 7, deployment: 8, done: 9
  }.freeze
  PHASES = %w[investigation planning implementation review testing deployment].freeze

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

  # the work branch agents commit to
  def branch_name = "pipe/#{code.downcase}"

  def next_state
    idx = STATES[state.to_sym]
    STATES.key(idx + 1)&.to_s
  end

  # The most recent testing run, whose result decides whether a pull request
  # opens ready or as a draft.
  def last_test_run
    phase_runs.select { |r| r.phase == "testing" && r.tests_passed.present? }.max_by(&:id)
  end

  def tests_failed? = last_test_run&.tests_failed.to_i.positive?

  # "no suite ran" is not the same as "the suite passed". A pull request must
  # not present unverified work as ready.
  def tests_ran?
    phase_runs.any? { |r| r.phase == "testing" && r.tests_executed }
  end

  # A suite that was made to stop asking is not a suite that passed.
  def tests_weakened? = phase_runs.any? { |r| r.phase == "testing" && r.guard_flags.any? }

  def guard_flags = phase_runs.select { |r| r.phase == "testing" }.flat_map(&:guard_flags)

  def verification_red? = tests_failed? || !tests_ran? || tests_weakened?

  def gated?
    ticket_gates.pending.exists?
  end

  def blocked_by_question?
    Question.pending.exists?(ticket_code: code)
  end

  # The last review that actually reported. Kept visible after the ticket
  # moves on: unresolved blocking findings are the reason to read the PR
  # carefully, and they are otherwise buried in a run log.
  def last_review
    phase_runs.to_a
              .select { |r| r.phase == "review" && r.review_findings.any? }
              .max_by { |r| r.started_at || Time.at(0) }
  end

  def current_phase_run
    if phase_runs.loaded?
      phase_runs.select { |r| r.phase == state }.max_by { |r| r.started_at || Time.at(0) }
    else
      phase_runs.where(phase: state).order(:started_at).last
    end
  end

  # Editing is for parked tickets only — changing one mid-run races the agent.
  def editable?
    %w[draft ready ready_to_implement].include?(state)
  end

  # Anything can be deleted except a ticket whose run is actively executing.
  def deletable?
    !(Ticket::PHASES.include?(state) && current_phase_run&.status == "running")
  end

  # An agent run owns this ticket's progression while it executes.
  def live_run?
    current_phase_run&.runner == "claude"
  end

  def deps_satisfied?
    pending_dep_codes.empty?
  end

  def pending_dep_codes
    return [] if dep_codes.blank?

    Ticket.where(code: dep_codes).where.not(state: :done).pluck(:code)
  end

  # First active blocker, or nil. Drives the derived Blocked board column —
  # the ticket keeps its state and resumes automatically once cleared.
  def blocker
    return { type: "clarification", label: "clarification needed" } if blocked_by_question?
    return { type: "gate", label: "awaiting approval" } if gated?
    return { type: "failed", label: "run failed — retry" } if current_phase_run&.status == "failed"

    if %w[ready ready_to_implement].include?(state) && !deps_satisfied?
      { type: "dependency", label: "waiting on #{pending_dep_codes.join(', ')}" }
    end
  end

  def agent_label
    agent&.name || (ready? ? "queued" : "unassigned")
  end
end
