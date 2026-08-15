# Prompts for the live RFC flow: a read-only Scout investigation and an
# Architect planning pass, both ending in structured JSON the app parses.
# When a custom harness is detected, its own commands are invoked instead
# (e.g. /opsx:explore for investigation, /opsx:propose for planning) with the
# JSON contract appended so the UI can still extract findings and tickets.
module RfcPrompts
  INVESTIGATE_CONTRACT = <<~TXT.freeze
    End your FINAL message with only a fenced json block in exactly this shape:

    ```json
    {
      "trace": [{"mark": "✓", "text": "a concrete finding"},
                 {"mark": "!", "text": "a risk or unknown"}],
      "questions": [{"q": "a decision you cannot make yourself",
                      "why": "why it matters",
                      "opts": ["Option A", "Option B"]}]
    }
    ```

    trace: 4-8 findings, mark "✓" for facts, "!" for risks/unknowns.
    questions: 0-3 genuine product decisions, each with 2-3 short options.
  TXT

  PLAN_CONTRACT = <<~TXT.freeze
    End your FINAL message with only a fenced json block in exactly this shape:

    ```json
    {
      "change": "kebab-case-change-name",
      "tickets": [
        {"title": "imperative ticket title", "repo": "REPO",
         "estimate": "1h 20m", "risky": false, "tag": "core",
         "depends_on": []},
        {"title": "second ticket", "repo": "REPO",
         "estimate": "40m", "risky": false, "tag": "tests",
         "depends_on": [1]}
      ]
    }
    ```

    depends_on lists 1-based indexes of prerequisite tickets in this plan.
    tag is one word (schema/core/api/tests/risky/docs). Mark risky: true
    for anything touching money, migrations or destructive operations.
  TXT

  module_function

  def investigate(rfc, targets, setting = Setting.instance)
    invocation = Harness.phase_invocation("investigation", setting)
    return harness_investigate(rfc, targets, invocation, setting) if invocation

    <<~TXT
      You are the Scout agent in an automated SDLC pipeline. A feature request
      came in for this workspace:

      "#{rfc.body}"

      Workspace layout: the current directory contains the project(s):
      #{targets.join(', ')}.

      Investigate READ-ONLY (do not modify any files): find the relevant code
      paths, existing related functionality, history and risks. If an
      openspec/ directory exists, check whether existing specs cover this.

      #{INVESTIGATE_CONTRACT}
    TXT
  end

  def plan(rfc, targets, setting = Setting.instance)
    invocation = Harness.phase_invocation("planning", setting)
    return harness_plan(rfc, targets, invocation, setting) if invocation

    <<~TXT
      You are the Architect agent in an automated SDLC pipeline. Turn this
      feature request into an ordered ticket plan.

      #{plan_context(rfc)}

      Valid repo targets (use ONLY these for "repo"):
      #{targets.join(', ')}

      Produce 2-6 tickets in dependency order, each small enough for one
      agent session.

      #{PLAN_CONTRACT.gsub('REPO', targets.first.to_s)}
    TXT
  end

  def harness_investigate(rfc, targets, invocation, setting)
    agents = Harness.phase_agents("investigation", setting)
    <<~TXT
      #{invocation} #{rfc.body}

      Pipeline context: you are running non-interactively inside an automated
      SDLC pipeline. Never ask the user anything or wait for input — capture
      open decisions as questions in the JSON below instead. Investigate
      READ-ONLY. The workspace projects are reachable from here:
      #{targets.join(', ')}.
      #{"Project agents available for delegation via the Task tool: #{agents.join(', ')}.\n" if agents.any?}
      #{INVESTIGATE_CONTRACT}
    TXT
  end

  def harness_plan(rfc, targets, invocation, setting)
    agents = Harness.phase_agents("planning", setting)
    <<~TXT
      #{invocation} #{rfc.body}

      Pipeline context: you are running non-interactively inside an automated
      SDLC pipeline. Never ask the user anything — create the change and ALL
      of its artifacts (proposal, design, tasks) now, deriving the change name
      yourself.

      #{plan_context(rfc)}

      Valid repo targets for tickets (use ONLY these): #{targets.join(', ')}.
      #{"Project agents available for delegation via the Task tool: #{agents.join(', ')}.\n" if agents.any?}
      After the artifacts are written, map the change's tasks onto 2-6
      pipeline tickets.

      #{PLAN_CONTRACT.gsub('REPO', targets.first.to_s)}
    TXT
  end

  def plan_context(rfc)
    answers = rfc.questions.filter_map do |q|
      answer = rfc.answers[q["key"]]
      "- #{q['q']} → #{answer || 'no preference given'}"
    end
    <<~TXT.strip
      Request: "#{rfc.body}"

      Investigation findings:
      #{rfc.trace.map { |t| "- [#{t['mark']}] #{t['text']}" }.join("\n")}

      Decisions from the user:
      #{answers.presence&.join("\n") || '- none'}
    TXT
  end
end
