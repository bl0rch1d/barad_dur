# Prompts handed to the headless agent for each pipeline phase.
# Deliberately artifact-oriented: every phase leaves something reviewable.
#
# When a custom harness is detected (Harness), mapped phases invoke the
# harness's own commands/skills inside the harness repo instead of the
# built-in prompts below.
module PhasePrompts
  # Grooming contracts: investigation may surface clarification questions
  # (parking the ticket as Blocked · clarification); planning reports the
  # openspec change, dependencies on existing tickets, and optional splits.
  QUESTIONS_CONTRACT = <<~TXT.freeze

    If (and ONLY if) you hit product decisions you cannot make yourself, end
    your FINAL message with a fenced json block:
    ```json
    {"questions": [{"q": "the decision", "why": "why it matters",
                    "opts": ["Option A", "Option B"]}]}
    ```
    0-2 questions, each with 2-3 short options. Omit the block entirely when
    nothing needs the user.
  TXT

  PLANNING_CONTRACT = <<~TXT.freeze

    End your FINAL message with a fenced json block:
    ```json
    {"change": "kebab-case-change-name-or-null",
     "summary": "2-3 sentence summary of what will be built and why",
     "technical_notes": "key files, approach, risks — a short paragraph",
     "acceptance_criteria": ["verifiable outcome 1", "verifiable outcome 2"],
     "depends_on": ["ALG-12"],
     "additional_tickets": [{"title": "...", "estimate": "40m", "risky": false}]}
    ```
    change: the openspec change you created (null if none).
    acceptance_criteria: 2-6 concrete, verifiable outcomes.
    depends_on: existing board ticket codes this work must wait for (usually []).
    additional_tickets: ONLY when this ticket is too big for one agent
    session — parts split out to run after it (usually []).
  TXT

  TESTING_CONTRACT = <<~TXT.freeze

    End your FINAL message with a fenced json block reporting the results:
    ```json
    {"command": "the test command you ran", "passed": 12, "failed": 0}
    ```
    Report the FINAL counts (after any fixes you committed).
  TXT

  module_function

  # Full execution plan for a phase run: prompt, working directory and extra
  # CLI args. Harness-mapped phases run in the harness repo with the whole
  # workspace reachable; everything else uses the built-in prompt in the
  # ticket's repo. Grooming phases carry structured-output contracts.
  def execution(ticket, phase, repo_path, setting = Setting.instance)
    invocation = Harness.phase_invocation(phase, setting)
    plan =
      if invocation && (phase != "implementation" || change_ref(ticket).present?)
        info = Harness.detect(setting)
        { prompt: harness_prompt(ticket, phase, invocation, setting),
          chdir: info.path,
          extra_args: ["--add-dir", Workspace.root(setting).to_s] }
      else
        { prompt: build(ticket, phase), chdir: repo_path, extra_args: [] }
      end
    plan[:prompt] += contract_for(ticket, phase)
    plan
  end

  def contract_for(ticket, phase)
    case phase
    when "investigation" then QUESTIONS_CONTRACT + board_context(ticket)
    when "planning"      then PLANNING_CONTRACT + board_context(ticket)
    when "testing"       then TESTING_CONTRACT
    else ""
    end
  end

  def board_context(ticket)
    others = Ticket.on_board.where.not(code: ticket.code).order(:code).limit(20)
    return "" if others.empty?

    "\nOpen tickets on the board — link genuine dependencies via their codes " \
    "and do NOT duplicate their work:\n" +
      others.map { |t| "- #{t.code}: #{t.title} [#{t.state}]" }.join("\n") + "\n"
  end

  # The openspec change a ticket belongs to (set when pushed from a
  # harness-planned RFC) — /opsx:apply needs it.
  def change_ref(ticket)
    ticket.artifacts.find { |a| a.start_with?("openspec change: ") }
          &.delete_prefix("openspec change: ")
  end

  def harness_prompt(ticket, phase, invocation, setting = Setting.instance)
    argument =
      case phase
      when "implementation" then change_ref(ticket)
      else "#{ticket.code}: #{ticket.title}"
      end
    agents = Harness.phase_agents(phase, setting)
    scope = Workspace.subpath(ticket.repo)

    <<~TXT
      #{invocation} #{argument}

      Pipeline context: you are running non-interactively as the #{role_for(phase)}
      agent for ticket #{ticket.code} ("#{ticket.title}") targeting repository
      #{ticket.repo}#{scope ? " (scope: #{scope} subdirectory)" : ""}.
      #{"Draft description from the user:\n#{ticket.description}\n" if ticket.description.present?}
      #{"The reviewer requested changes — address this feedback first:\n#{ticket.feedback}\n" if ticket.feedback.present? && %w[implementation review].include?(phase)}
      Never ask the user questions interactively — make reasonable choices and note them.
      #{"Project agents available for delegation via the Task tool: #{agents.join(', ')}.\n" if agents.any?}
      Work autonomously until the #{phase} outcome is complete, then summarize
      what you did.
    TXT
  end

  def build(ticket, phase)
    header = <<~TXT
      You are the #{role_for(phase)} agent in an automated SDLC pipeline working on
      ticket #{ticket.code}: "#{ticket.title}".
      Repository: current working directory. Work autonomously.
      If an openspec/ directory exists, treat its specs as the contract.
    TXT
    header += "Draft description from the user:\n#{ticket.description}\n" if ticket.description.present?
    if ticket.feedback.present? && %w[implementation review].include?(phase)
      header += "The reviewer requested changes — address this feedback first:\n#{ticket.feedback}\n"
    end
    if (sub = Workspace.subpath(ticket.repo))
      header += "Scope: focus your work on the `#{sub}` subdirectory of this repository (monorepo sub-project).\n"
    end
    header + body_for(ticket, phase)
  end

  def role_for(phase)
    { "investigation" => "Scout", "planning" => "Architect", "implementation" => "Builder",
      "review" => "Critic", "testing" => "Tester", "deployment" => "Shipper" }.fetch(phase, "Builder")
  end

  def body_for(ticket, phase)
    plan_file = "openspec/changes/#{ticket.code.downcase}-plan.md"
    case phase
    when "investigation" then <<~TXT
      Investigate the codebase for this ticket. Locate the relevant code paths,
      call sites and history. Do NOT modify any files. Finish with a concise
      report: root cause / relevant context, affected files, risks.
    TXT
    when "planning" then <<~TXT
      Produce an implementation plan for this ticket and write it to
      #{plan_file} (create directories as needed). The plan must list ordered
      steps, files to change, and how the change will be tested. Do not change
      any other files.
    TXT
    when "implementation" then <<~TXT
      Implement this ticket now. A work branch is already checked out. Follow
      #{plan_file} if it exists. Make focused git commits as you go (git add +
      git commit with clear messages). Keep the change minimal and cohesive.
    TXT
    when "review" then <<~TXT
      Review the diff of this branch against its merge base like a strict code
      reviewer: correctness, spec compliance, edge cases. Fix any real problems
      you find with additional commits. Finish with a verdict summary.
    TXT
    when "testing" then <<~TXT
      Infer how this repository runs its tests and run them. If failures relate
      to this ticket's change, fix them and commit. Finish by reporting the
      test command used and the pass/fail counts.
    TXT
    when "deployment" then <<~TXT
      Prepare this change for release: append a changelog entry for this ticket
      to CHANGELOG.md (create it if missing) and commit it. Do NOT push, tag,
      or deploy anywhere.
    TXT
    else
      "Complete the #{phase} phase for this ticket and report what you did.\n"
    end
  end
end
