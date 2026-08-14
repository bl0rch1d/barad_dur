# Prompts handed to the headless agent for each pipeline phase.
# Deliberately artifact-oriented: every phase leaves something reviewable.
module PhasePrompts
  module_function

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
