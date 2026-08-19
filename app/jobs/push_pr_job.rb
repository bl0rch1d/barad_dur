require "open3"

# Opt-in tribute to the far lands: pushes a ticket's work branch to origin
# and opens a pull request via the gh CLI. Never runs automatically.
class PushPrJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    repo = Workspace.repo_path(ticket.repo)
    return fail!(ticket, "repository not in workspace") unless repo

    branch = ticket.branch_name
    unless run_ok?(repo, "git", "rev-parse", "--verify", branch)
      return fail!(ticket, "branch #{branch} not found")
    end
    unless run_ok?(repo, "git", "remote", "get-url", "origin")
      return fail!(ticket, "no origin remote on #{ticket.repo}")
    end

    out, ok = run(repo, "git", "push", "-u", "origin", branch)
    return fail!(ticket, "push failed: #{out.lines.last.to_s.strip.truncate(100)}") unless ok

    Event.record!(phase_tag: "DEPLOY", ticket: ticket, agent_name: "Shipper",
                  meta: "origin", text: "Pushed #{branch} to origin")

    gh = ENV["GH_BIN"].presence || "gh"
    body = pr_body(ticket)
    # A red suite still gets a pull request — you need to see the work — but
    # as a draft, so it cannot be mistaken for something ready to merge.
    draft = ticket.verification_red?
    args = ["pr", "create", "--title", "#{pr_prefix(ticket)}#{ticket.code}: #{ticket.title}",
            "--body", body, "--head", branch]
    args << "--draft" if draft
    out, ok = run(repo, gh, *args)
    if ok
      url = out[%r{https://\S+}]
      ticket.update!(pr_url: url, artifacts: ticket.artifacts | ["PR: #{url || 'opened'}"])
      Event.record!(phase_tag: "DEPLOY", tone: "var(--ok)", ticket: ticket, agent_name: "Shipper",
                    text: "Pull request opened for #{ticket.code}#{" — #{url}" if url}")
    else
      fail!(ticket, "gh pr create failed: #{out.lines.last.to_s.strip.truncate(120)}")
      return
    end
    PipelineEngine.broadcast
  end

  private

  # The title must say why a pull request is a draft — "unverified" and
  # "failing" are different problems and the reader has to act differently.
  def pr_prefix(ticket)
    return "[tests failing] " if ticket.tests_failed?
    return "[suite weakened] " if ticket.tests_weakened?
    return "[unverified] " unless ticket.tests_ran?

    ""
  end

  def pr_body(ticket)
    parts = []
    parts << ticket.description if ticket.description.present?
    if ticket.acceptance_criteria.any?
      parts << "### Acceptance criteria\n" + ticket.acceptance_criteria.map { |c| "- [ ] #{c}" }.join("\n")
    end
    parts << verification_section(ticket)
    parts << "---\nForged by [Barad-dûr](https://github.com/bl0rch1d/barad_dur) · ticket #{ticket.code}"
    parts.compact.join("\n\n")
  end

  # A reviewer reading this on GitHub cannot see the tower, so the pull request
  # has to carry its own verification story — including the parts that are bad
  # news, which is the whole reason for writing it down.
  def verification_section(ticket)
    run = ticket.phase_runs.select { |r| r.phase == "testing" }.max_by { |r| r.started_at || Time.at(0) }
    lines = ["### Verification"]

    if run.nil? || !run.tests_executed?
      lines << "No suite ran — nothing here has been verified automatically."
    else
      lines << "`#{run.tests_command || 'tests'}` — **#{run.tests_passed.to_i} passed, #{run.tests_failed.to_i} failed**"
      Array(run.test_suites).each do |suite|
        lines << if suite["skipped"]
                   "- #{suite['kind']}: not run — #{suite['skipped']}"
                 else
                   "- #{suite['kind']}: #{suite['passed'].to_i} passed, #{suite['failed'].to_i} failed (`#{suite['command']}`)"
                 end
      end
    end

    if ticket.tests_weakened?
      lines << "\n> [!WARNING]\n> The test suite was weakened on this branch — " \
               "#{TestGuard.summary(ticket.guard_flags)}. Check that each was deliberate:"
      ticket.guard_flags.first(10).each { |f| lines << "> - `#{f['path']}` — #{f['detail']}" }
    end

    lines.join("\n")
  end

  def run(repo, *cmd)
    out, status = Open3.capture2e(*cmd, chdir: repo)
    [out, status.success?]
  rescue Errno::ENOENT
    ["#{cmd.first}: command not found", false]
  end

  def run_ok?(repo, *cmd)
    run(repo, *cmd).last
  end

  def fail!(ticket, reason)
    Event.record!(phase_tag: "DEPLOY", tone: "var(--err)", ticket: ticket, agent_name: "Shipper",
                  text: "Push & PR failed for #{ticket.code}: #{reason}")
    PipelineEngine.broadcast
    false
  end
end
