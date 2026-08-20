require "json"

# Everything a phase needs to start, computed by Ruby and written to disk.
#
# The phase boundary belongs here, not to the next model. A prompt that says
# "work out which test command this project uses" is asking an agent to spend
# turns rediscovering a fact that a file read answers, and to guess when the
# turns run out. A prompt that says "the previous phase should have told you
# the base commit" is asking it to proceed on a hole. Both were how state
# crossed a phase boundary; both now arrive as JSON that was true when it was
# written and says plainly what is missing.
#
# One direction only: Ruby writes, the agent reads. Nothing here is ever
# edited by a phase, and where the brief disagrees with the prompt or the
# record, the brief wins.
module PhaseBrief
  VERSION = 1

  # The repo's own instructions to anyone working in it. A harness phase runs
  # with the harness as its working directory, so the target repo's CLAUDE.md
  # never auto-loads — without this, five of six phases would never see it.
  CONVENTION_FILES = %w[CLAUDE.md AGENTS.md .cursorrules CONTRIBUTING.md docs/CONTRIBUTING.md].freeze
  CONVENTION_BUDGET = 8_192

  module_function

  def write!(ticket, phase, repo_path)
    return nil if repo_path.blank?

    PhaseRecord.ensure!(repo_path, ticket.code)
    data = payload(ticket, phase, repo_path)
    file = path(repo_path, ticket.code)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, JSON.pretty_generate(data))
    file
  rescue SystemCallError, JSON::GeneratorError => e
    Rails.logger.warn { "phase brief not written for #{ticket.code}: #{e.class}: #{e.message}" }
    nil
  end

  def path(repo_path, code) = File.join(repo_path.to_s, ".pipe", "#{code.to_s.upcase}.brief.json")

  def payload(ticket, phase, repo_path)
    code = ticket.code
    base = GitRepo.base_branch(repo_path)
    contract = PhaseRecord.contract(repo_path, code)
    degraded = PhaseRecord.degraded(repo_path, code, phase)

    { "_v" => VERSION,
      "code" => code,
      "title" => ticket.title,
      "phase" => phase,
      "repo" => ticket.repo,
      "repo_path" => repo_path.to_s,
      "scope_path" => Workspace.subpath(ticket.repo),
      "branch" => ticket.branch_name,
      "base_branch" => base,
      "base_sha" => base && rev_parse(repo_path, base),
      "description" => ticket.description.presence,
      # The contract's copy is untruncated; the ticket column clips each
      # criterion to 200 characters, which a GIVEN/WHEN/THEN clause exceeds
      # routinely — and review would then be grading against clipped text.
      "acceptance_criteria" => criteria(ticket, contract),
      "technical_notes" => ticket.technical_notes.presence,
      "answered_questions" => answered(code),
      "feedback" => ticket.feedback.presence,
      "is_rework" => ticket.feedback.present?,
      "rework_count" => ticket.phase_runs.where(phase: "implementation").count,
      "toolchain" => toolchain(repo_path, Workspace.subpath(ticket.repo)),
      "repo_conventions" => conventions(repo_path),
      "files_changed" => changed_files(repo_path, base),
      "untracked" => GitRepo.uncommitted(repo_path).select { |f| f["status"] == "??" }.map { |f| f["path"] },
      "record_path" => PhaseRecord.path(repo_path, code),
      "contract_path" => PhaseRecord.contract_path(repo_path, code),
      "out_path" => PhaseRecord.out_path(repo_path, code, phase),
      "degraded" => degraded,
      "board" => board(ticket) }
  end

  def criteria(ticket, contract)
    from_contract = Array(contract&.dig("criteria")).filter_map { |c| c["text"].to_s.presence }
    return from_contract if from_contract.any?

    ticket.acceptance_criteria
  end

  def answered(code)
    Question.where(ticket_code: code).where.not(chosen: [nil, ""]).order(:asked_at)
            .map { |q| { "q" => q.body.to_s, "chosen" => q.chosen.to_s } }
  end

  # Every entry says where it came from and whether its binary is actually on
  # PATH. "runnable": false is not the same as "no such tool", and neither is
  # ever a pass — a phase that cannot tell them apart reports green for a
  # linter that was never installed.
  def toolchain(repo_path, scope = nil)
    Toolchain.detect(repo_path, scope).map do |command|
      { "kind" => command.kind, "command" => command.command, "because" => command.because,
        "runnable" => runnable?(command.command) }
    end
  end

  def runnable?(command)
    binary = command.to_s.split.first
    return true if binary.nil? || binary.include?("/")

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
       .any? { |dir| File.executable?(File.join(dir, binary)) }
  end

  def conventions(repo_path)
    budget = CONVENTION_BUDGET
    CONVENTION_FILES.filter_map do |name|
      next if budget <= 0

      body = read_capped(File.join(repo_path.to_s, name), budget) or next

      budget -= body.bytesize
      { "path" => name, "text" => body }
    end
  end

  def changed_files(repo_path, base)
    return [] if base.blank?

    out, ok = GitRepo.capture(repo_path, "diff", "--name-only", "#{base}...HEAD")
    ok ? out.lines.map(&:chomp).reject(&:empty?).first(500) : []
  end

  # Enough of the board to link a real dependency without duplicating work,
  # and no more — this is context, not the ticket's own specification.
  def board(ticket)
    Ticket.on_board.where.not(code: ticket.code).order(:code).limit(20)
          .map { |t| { "code" => t.code, "title" => t.title, "state" => t.state } }
  end

  def rev_parse(repo_path, ref)
    out, ok = GitRepo.capture(repo_path, "rev-parse", ref)
    ok ? out.strip.presence : nil
  end

  def read_capped(file, budget)
    return nil unless File.file?(file)

    File.read(file, budget).to_s.force_encoding(Encoding::UTF_8).scrub.strip.presence
  rescue SystemCallError
    nil
  end
end
