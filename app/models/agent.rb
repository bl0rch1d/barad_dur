class Agent < ApplicationRecord
  STATUSES = %w[idle running waiting].freeze

  has_many :tickets
  has_many :spend_entries

  # today's spend for this agent, straight from the ledger
  def cost_today = spend_entries.today.sum(:amount)

  validates :name, :abbr, :role, :llm_model, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position) }
  scope :idle, -> { where(status: "idle") }

  # The roster agent staffing a phase — names vary (harness-mapped rosters
  # use e.g. "explorer"), roles are stable.
  # What this role is for, in one sentence a non-specialist can act on.
  BLURBS = {
    "investigation" => "Reads the code before anything is decided. Never edits — it reports what exists, what it affects, and what is unclear.",
    "planning" => "Turns the findings into an approach and writes the acceptance criteria every later phase is judged against.",
    "implementation" => "Writes the code on the ticket's own branch, committing as it goes.",
    "review" => "Reads the diff as a critic that did not write it, and checks the work against the criteria planning wrote.",
    "testing" => "Runs the linters, unit tests, regression and end-to-end suites the project has, and reports what passed, failed or could not run.",
    "deployment" => "Prepares the finished work to land — the changelog entry and anything else the repo expects before a merge."
  }.freeze

  def blurb = BLURBS.fetch(role, "Serves the #{role} phase of the pipeline.")

  # The model this agent actually runs on. Unpinned agents follow the realm.
  def effective_model(setting = Setting.instance)
    model_id.presence || setting.orchestrator_model
  end

  def model_label(setting = Setting.instance)
    Setting::ORCHESTRATOR_MODELS[effective_model(setting)] || effective_model(setting)
  end

  def pinned? = model_id.present?

  def self.for_phase(phase)
    ordered.detect { |a| a.role.to_s.start_with?(phase.to_s) } || ordered.first
  end

  def tone
    case status
    when "running" then "var(--accent)"
    when "waiting" then "var(--warn)"
    else "var(--tx3)"
    end
  end

  def soft
    case status
    when "running" then "var(--accent-soft)"
    when "waiting" then "var(--warn-soft)"
    else "var(--sunken)"
    end
  end
end
