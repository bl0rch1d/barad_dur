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

  # A reviewer that edits the code has, on the next round, reviewed its own
  # work — so review reports and implementation fixes. That only holds
  # together if a blocking finding actually sends the ticket back, which is
  # what the verdict here drives.
  REVIEW_CONTRACT = <<~TXT.freeze

    End your FINAL message with a fenced json block:
    ```json
    {"verdict": "changes_requested",
     "findings": [{"severity": "blocking", "file": "app/models/order.rb:88",
                   "what": "the cache key omits the venue",
                   "why": "two venues collide and return each other's prices"}]}
    ```
    verdict: "pass" when nothing blocking remains, "changes_requested" otherwise.
    severity: "blocking" for anything that makes the change wrong, unsafe, or
    incomplete against the acceptance criteria above — everything else is
    "minor". Be strict about what blocks and honest about what does not; a
    blocking finding sends the whole ticket back for rework.
    Report findings — do NOT fix them yourself.
  TXT

  TESTING_CONTRACT = <<~TXT.freeze

    End your FINAL message with a fenced json block reporting what you ran.
    List every suite separately, including the ones you could not run and why:
    ```json
    {"command": "bundle exec rspec", "passed": 128, "failed": 0,
     "suites": [
       {"kind": "lint", "command": "bundle exec rubocop", "passed": 1, "failed": 0},
       {"kind": "unit", "command": "bundle exec rspec spec/models", "passed": 96, "failed": 0},
       {"kind": "e2e", "command": "yarn cypress run", "skipped": "needs a running server"}
     ]}
    ```
    "command", "passed" and "failed" are the totals across everything you ran —
    the FINAL counts, after any fixes you committed. Omit "suites" only if the
    project genuinely has one command and nothing else.
  TXT

  module_function

  # Full execution plan for a phase run: prompt, working directory and extra
  # CLI args. Harness-mapped phases run in the harness repo with the whole
  # workspace reachable; everything else uses the built-in prompt in the
  # ticket's repo. Grooming phases carry structured-output contracts.
  def execution(ticket, phase, repo_path, setting = Setting.instance, run = nil)
    invocation = Harness.phase_invocation(phase, setting)
    plan =
      if invocation
        info = Harness.detect(setting)
        # The harness runs from its own repo, so the phase must be told where
        # the ticket's code actually is — a bare git call here would operate
        # on the harness checkout.
        { prompt: harness_prompt(ticket, phase, invocation, setting, repo_path),
          chdir: info.path,
          extra_args: ["--add-dir", Workspace.root(setting).to_s] }
      else
        { prompt: build(ticket, phase), chdir: repo_path, extra_args: [] }
      end
    contract = contract_for(ticket, phase)
    contract += PhaseOutput.instruction(run) if contract.present? && run
    plan[:prompt] += contract
    plan
  end

  def contract_for(ticket, phase)
    case phase
    when "investigation" then QUESTIONS_CONTRACT + board_context(ticket)
    when "planning"      then PLANNING_CONTRACT + board_context(ticket)
    when "review"        then REVIEW_CONTRACT
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

  def harness_prompt(ticket, phase, invocation, setting = Setting.instance, repo_path = nil)
    # /opsx:apply resolves a change by slug, so pass it when we have one —
    # but never let its absence mean "no harness implementation at all", and
    # always name the ticket in the body so identity survives either way.
    argument = (phase == "implementation" && change_ref(ticket).presence) ||
               "#{ticket.code}: #{ticket.title}"
    agents = Harness.phase_agents(phase, setting)
    scope = Workspace.subpath(ticket.repo)

    <<~TXT
      #{invocation} #{argument}

      Pipeline context: you are running non-interactively as the #{role_for(phase)}
      agent for ticket #{ticket.code} ("#{ticket.title}") targeting repository
      #{ticket.repo}#{scope ? " (scope: #{scope} subdirectory)" : ""}.
      #{"The repository under work is at #{repo_path} — your working directory is the harness repo, so pass -C #{repo_path} to git and read files from there.\n" if repo_path}
      #{"The openspec change for this ticket is #{change_ref(ticket)}.\n" if change_ref(ticket)}
      #{spec_block(ticket, phase)}
      #{"Never ask the user questions interactively — make reasonable choices and note them." unless phase == "investigation"}
      #{"Project agents available for delegation via the Task tool: #{agents.join(', ')}.\n" if agents.any?}
      Work autonomously until the #{phase} outcome is complete, then summarize
      what you did.
    TXT
  end

  # What this ticket is FOR and what "done" means — the specification the
  # planning phase produced. Without it every later phase re-derives the goal
  # from the code, which is grading the change against itself.
  def spec_block(ticket, phase = nil)
    parts = []
    parts << "What the user asked for:\n#{ticket.description}\n" if ticket.description.present?

    if ticket.acceptance_criteria.any?
      list = ticket.acceptance_criteria.each_with_index.map { |c, i| "  #{i + 1}. #{c}" }.join("\n")
      parts << "Acceptance criteria — written during planning, before any code. " \
               "This is the contract:\n#{list}\n"
    end
    parts << "Technical notes from planning (context, not the contract):\n#{ticket.technical_notes}\n" if ticket.technical_notes.present?

    # A question the user answered is a decision that binds every later phase.
    answered = Question.where(ticket_code: ticket.code).where.not(chosen: [nil, ""]).order(:asked_at)
    if answered.any?
      decisions = answered.map { |q| "  - #{q.body.to_s.truncate(160)} → #{q.chosen}" }.join("\n")
      parts << "Decisions you already have from the user — treat these as settled, " \
               "do not ask again and do not contradict them:\n#{decisions}\n"
    end

    if ticket.feedback.present?
      parts << if phase == "review"
                 "A previous review round requested these changes — verify they were addressed:\n#{ticket.feedback}\n"
               else
                 "The reviewer requested changes — address this feedback first:\n#{ticket.feedback}\n"
               end
    end
    parts.join("\n")
  end

  def build(ticket, phase)
    header = <<~TXT
      You are the #{role_for(phase)} agent in an automated SDLC pipeline working on
      ticket #{ticket.code}: "#{ticket.title}".
      Repository: current working directory. Work autonomously.
      If an openspec/ directory exists, treat its specs as the contract.
    TXT
    header += spec_block(ticket, phase)
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
      reviewer: correctness, compliance with the acceptance criteria above,
      edge cases, and anything the change breaks elsewhere.

      Read only. Do NOT edit, commit, or fix what you find — report it. A
      blocking finding sends the ticket back to implementation, where it is
      fixed by an agent that did not also decide it was a problem.

      Judge the change that is here, not the change you would have written.
    TXT
    when "testing" then <<~TXT
      Verify this change properly — a pull request is opened for human review
      the moment you finish, so this is the last automated gate.

      Work out what this repository actually has and run everything that
      applies, in this order:

        1. Linters and formatters (rubocop, eslint, ruff, golangci-lint,
           prettier --check, or whatever the project configures). Fix what
           they flag in code you touched.
        2. The unit test suite.
        3. Regression and integration suites, if the project keeps them
           separate from unit tests.
        4. End-to-end or browser tests, if the project has them and they can
           run here. If they need a service you cannot start, say so plainly
           rather than skipping them silently.

      Look for the commands in the places projects keep them — package.json
      scripts, Rakefile, Makefile, tox.ini, CI workflow files, CONTRIBUTING —
      rather than guessing. Do not invent a command that does not exist.

      Fix failures caused by this ticket's change and commit the fixes. If a
      failure is pre-existing and unrelated, leave it alone and report it as
      pre-existing. Never weaken, skip or delete a test to make it pass.
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
