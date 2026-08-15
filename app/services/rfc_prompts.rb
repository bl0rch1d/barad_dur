# Prompts for the live RFC flow: a read-only Scout investigation and an
# Architect planning pass, both ending in structured JSON the app parses.
module RfcPrompts
  module_function

  def investigate(rfc, targets)
    <<~TXT
      You are the Scout agent in an automated SDLC pipeline. A feature request
      came in for this workspace:

      "#{rfc.body}"

      Workspace layout: the current directory contains the project(s):
      #{targets.join(', ')}.

      Investigate READ-ONLY (do not modify any files): find the relevant code
      paths, existing related functionality, history and risks. If an
      openspec/ directory exists, check whether existing specs cover this.

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
  end

  def plan(rfc, targets)
    answers = rfc.questions.filter_map do |q|
      answer = rfc.answers[q["key"]]
      "- #{q['q']} → #{answer || 'no preference given'}"
    end
    <<~TXT
      You are the Architect agent in an automated SDLC pipeline. Turn this
      feature request into an ordered ticket plan.

      Request: "#{rfc.body}"

      Investigation findings:
      #{rfc.trace.map { |t| "- [#{t['mark']}] #{t['text']}" }.join("\n")}

      Decisions from the user:
      #{answers.presence&.join("\n") || '- none'}

      Valid repo targets (use ONLY these for "repo"):
      #{targets.join(', ')}

      Produce 2-6 tickets in dependency order, each small enough for one
      agent session. End your FINAL message with only a fenced json block:

      ```json
      {
        "tickets": [
          {"title": "imperative ticket title", "repo": "#{targets.first}",
           "estimate": "1h 20m", "risky": false, "tag": "core",
           "depends_on": []},
          {"title": "second ticket", "repo": "#{targets.first}",
           "estimate": "40m", "risky": false, "tag": "tests",
           "depends_on": [1]}
        ]
      }
      ```

      depends_on lists 1-based indexes of prerequisite tickets in this plan.
      tag is one word (schema/core/api/tests/risky/docs). Mark risky: true
      for anything touching money, migrations or destructive operations.
    TXT
  end
end
