# Lands approved work the way this realm was configured to land it. Called
# when you approve a ticket's verdict gate, or press the drawer's button.
#
#   pull_request — merge the open PR on GitHub (the default)
#   local_merge  — --no-ff merge into the default branch, never pushed
#   manual       — nothing is merged; the branch is left for you
module LandWork
  Result = Struct.new(:ok, :message, keyword_init: true)

  module_function

  def call(ticket)
    result = case Features.landing
             when "pull_request" then merge_pull_request(ticket)
             when "local_merge"  then merge_locally(ticket)
             else Result.new(ok: true, message: "left on #{ticket.branch_name} for you to land")
             end

    if result.ok
      ticket.update!(artifacts: ticket.artifacts | [result.message])
      PipelineEngine.manual_ship!(ticket, result.message)
      ArchiveChangeJob.perform_later(ticket.id)
    else
      # Keep the ticket where it is with a fresh gate, so it can be retried
      # once whatever blocked the merge is dealt with.
      Event.record!(phase_tag: "DEPLOY", tone: "var(--err)", ticket_code: ticket.code,
                    agent_name: "you", text: "Could not land #{ticket.code}: #{result.message}")
      unless ticket.gated? || ticket.done?
        ticket.ticket_gates.create!(to_state: Ticket::STATES[:done],
                                    reason: "#{ticket.code} could not be landed — #{result.message.truncate(90)}")
      end
      PipelineEngine.broadcast
    end
    result
  end

  def merge_pull_request(ticket)
    # Approving is your verdict on the work; whether a PR exists to merge is a
    # mechanical detail. Refusing here would strand the ticket forever when gh
    # is unconfigured, so say plainly what did and did not happen.
    if ticket.pr_url.blank?
      return Result.new(ok: true, message: "marked shipped — no pull request was open, #{ticket.branch_name} is unmerged")
    end

    repo = Workspace.repo_path(ticket.repo)
    return Result.new(ok: false, message: "#{ticket.repo} is not in the workspace") unless repo

    out, status = Open3.capture2e(gh_env, gh_bin, "pr", "merge", ticket.pr_url,
                                  "--merge", "--delete-branch", chdir: repo)
    if status.success?
      Result.new(ok: true, message: "merged pull request #{ticket.pr_url}")
    else
      Result.new(ok: false, message: gh_reason(out))
    end
  rescue Errno::ENOENT
    Result.new(ok: false, message: "the gh CLI is not installed")
  end

  def merge_locally(ticket)
    result = BranchMerger.call(ticket)
    Result.new(ok: result.ok, message: result.message)
  end

  # gh is wordy on failure; the last non-empty line carries the reason.
  def gh_reason(out)
    line = out.to_s.lines.map(&:strip).reject(&:empty?).last.to_s
    return "the pull request needs a review or a passing check before it can merge" if line.match?(/not mergeable|required status|review/i)

    line.presence&.truncate(140) || "gh pr merge failed"
  end

  def gh_bin = ENV["GH_BIN"].presence || "gh"

  def gh_env
    token = ENV["GH_TOKEN"].presence
    token ? { "GH_TOKEN" => token } : {}
  end
end
