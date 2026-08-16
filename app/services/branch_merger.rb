require "open3"

# Lands a ticket's work branch (pipe/<code>) into the repository's base
# branch with a merge commit. Local only — the pipeline never pushes.
class BranchMerger
  Result = Struct.new(:ok, :message, keyword_init: true)

  class << self
    def call(ticket)
      repo = Workspace.repo_path(ticket.repo)
      return failure("repository #{ticket.repo.inspect} not in workspace") unless repo

      branch = "pipe/#{ticket.code.downcase}"
      return failure("branch #{branch} not found") unless git?(repo, "rev-parse", "--verify", branch)

      base = %w[main master].find { |b| git?(repo, "rev-parse", "--verify", b) }
      return failure("no main/master branch in #{ticket.repo}") unless base

      unless git?(repo, "checkout", base)
        return failure("cannot check out #{base} — uncommitted changes in the repo?")
      end

      message = "Merge #{branch}: #{ticket.title.truncate(60)} (#{ticket.code})"
      if git?(repo, "merge", "--no-ff", branch, "-m", message)
        Result.new(ok: true, message: "merged #{branch} into #{base}")
      else
        git?(repo, "merge", "--abort")
        failure("merge conflict with #{base} — resolve manually in the repo")
      end
    end

    private

    def failure(message)
      Result.new(ok: false, message: message)
    end

    def git?(repo, *args)
      _, status = Open3.capture2e("git", "-C", repo, *args)
      status.success?
    rescue Errno::ENOENT
      false
    end
  end
end
