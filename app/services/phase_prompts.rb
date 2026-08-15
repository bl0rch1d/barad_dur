# Prompts handed to the headless agent for each pipeline phase.
# Deliberately artifact-oriented: every phase leaves something reviewable.
#
# When a custom harness is detected (Harness), mapped phases invoke the
# harness's own commands/skills inside the harness repo instead of the
# built-in prompts below.
module PhasePrompts
  module_function

  # Full execution plan for a phase run: prompt, working directory and extra
  # CLI args. Harness-mapped phases run in the harness repo with the whole
  # workspace reachable; everything else uses the built-in prompt in the
  # ticket's repo.
  def execution(ticket, phase, repo_path, setting = Setting.instance)
    invocation = Harness.phase_invocation(phase, setting)
    if invocation && (phase != "implementation" || change_ref(ticket).present?)
      info = Harness.detect(setting)
      { prompt: harness_prompt(ticket, phase, invocation, setting),
        chdir: info.path,
        extra_args: ["--add-dir", Workspace.root(setting).to_s] }
    else
      { prompt: build(ticket, phase), chdir: repo_path, extra_args: [] }
    end
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
      Never ask the user questions — make reasonable choices and note them.
      #{"Project agents available for delegation via the Task tool: #{agents.join(', ')}.\n" if agents.any?}
      Work autonomously until the #{phase} outcome is complete, then summarize
      what you did.
    TXT
  end

  def build(ticket, phase)
    header = <<~TXT
      You are the #{role_for(phase)} agent in an automated SDLC pipeline working on
      ticket #{ticket.code}: "#{ticket.title}".
      Repository: current working directory. Work autonomously — no questions.
      If an openspec/ directory exists, treat its specs as the contract.
    TXT
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
