require "open3"

# Facts about a checkout the pipeline should ask for rather than assume.
module GitRepo
  CONVENTIONAL = %w[main master develop trunk].freeze

  module_function

  # The branch work is cut from, compared against and merged back into.
  #
  # Asked of the repository in descending order of authority: what the remote
  # says its HEAD is, what the repository is configured to default to, then the
  # conventional names. Guessing "main, else master" is wrong for any project
  # whose trunk is develop or trunk, and worse for one that renamed to main
  # while leaving a stale master behind — the diff then reads as an enormous
  # unrelated change and the merge lands on a branch nobody uses.
  def base_branch(repo)
    remote_head(repo) || configured_default(repo) || conventional(repo)
  end

  def remote_head(repo)
    out, ok = capture(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    return unless ok

    remote = out.strip.presence or return
    local = remote.delete_prefix("origin/")
    return local if exists?(repo, local)

    remote if exists?(repo, remote)
  end

  def configured_default(repo)
    out, ok = capture(repo, "config", "--get", "init.defaultBranch")
    return unless ok

    name = out.strip.presence
    name if name && exists?(repo, name)
  end

  def conventional(repo)
    CONVENTIONAL.find { |branch| exists?(repo, branch) }
  end

  def exists?(repo, ref)
    capture(repo, "rev-parse", "--verify", "--quiet", ref).last
  end

  # Paths the agent changed but never committed. They are invisible to
  # `git diff base...HEAD` and absent from the pull request, so work that
  # stops here is work that silently does not ship.
  def uncommitted(repo)
    out, ok = capture(repo, "status", "--porcelain")
    return [] unless ok

    out.lines.filter_map do |line|
      status, path = line.chomp.match(/\A(..) (.+)\z/)&.captures
      next unless path

      { "status" => status.strip.presence || "??", "path" => path }
    end
  end

  def capture(repo, *args)
    out, status = Open3.capture2e("git", "-C", repo.to_s, *args)
    [out, status.success?]
  rescue Errno::ENOENT, SystemCallError
    ["", false]
  end
end
