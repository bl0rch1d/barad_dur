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
    draft = ticket.tests_failed?
    args = ["pr", "create", "--title", "#{draft ? '[tests failing] ' : ''}#{ticket.code}: #{ticket.title}",
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

  def pr_body(ticket)
    parts = []
    parts << ticket.description if ticket.description.present?
    if ticket.acceptance_criteria.any?
      parts << "### Acceptance criteria\n" + ticket.acceptance_criteria.map { |c| "- [ ] #{c}" }.join("\n")
    end
    parts << "---\nForged by [Barad-dûr](https://github.com/bl0rch1d/barad_dur) · ticket #{ticket.code}"
    parts.join("\n\n")
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
