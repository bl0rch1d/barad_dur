require "open3"
require "monitor"

# The mounted workspace the pipeline can operate on. The host folder given by
# WORKSPACE_PATH is mounted at /workspace (the "mount root"); the wizard's
# folder chooser can then select any folder inside it as the active workspace
# root (persisted in Setting.setup["workspace_dir"]).
#
# Two layouts are supported and auto-detected:
#   :monorepo   — the chosen folder is itself a git repository
#   :multi_repo — the chosen folder contains git repositories
class Workspace
  PROJECT_MARKERS = %w[
    package.json Gemfile pyproject.toml setup.py go.mod Cargo.toml
    pom.xml build.gradle mix.exs composer.json CMakeLists.txt
  ].freeze

  # Scans shell out to git and walk directories on what is usually a slow
  # bind mount; they also run on every render (and every ~3s morph refresh).
  # Results are memoized in-process, keyed by directory. Folder navigation and
  # the specs rescan call refresh! explicitly, so the TTL only bounds how long
  # out-of-band filesystem changes stay unnoticed.
  CommitEntry = Struct.new(:sha, :message, :author, :committed_at)

  CACHE_TTL = 120
  CACHE_MUTEX = Mutex.new
  # Reentrant: cached blocks nest (openspec_repos wraps repos). Single-flights
  # scans so concurrent cache misses can't stampede the slow mount.
  SCAN_LOCK = Monitor.new

  class << self
    def refresh!
      CACHE_MUTEX.synchronize { @cache = {} }
    end

    # Public memoization hook for services scanning the workspace (Harness…),
    # sharing the same single-flight cache and refresh! lifecycle.
    def memo(key, ttl: CACHE_TTL, &block)
      cached(key, ttl: ttl, &block)
    end
    def mount_root
      Pathname.new(ENV.fetch("WORKSPACE_ROOT", "/workspace"))
    end

    # Active workspace root: mount root + the wizard-chosen subfolder.
    # Never escapes the mount root.
    def root(setting = Setting.instance)
      sub = setting.setup["workspace_dir"].to_s
      return mount_root if sub.blank?

      candidate = (mount_root + sub).cleanpath
      candidate.to_s.start_with?(mount_root.to_s) && candidate.directory? ? candidate : mount_root
    rescue ActiveRecord::ActiveRecordError
      mount_root
    end

    def layout(setting = Setting.instance)
      dir = root(setting)
      return :empty unless dir.directory?
      return :monorepo if dir.join(".git").exist?

      repos(setting).any? ? :multi_repo : :empty
    end

    def available?(setting = Setting.instance)
      repos(setting).any?
    end

    # [{ name:, path:, branch:, commits:, files: }, ...]
    # Monorepo → a single entry for the root repository itself.
    def repos(setting = Setting.instance)
      dir = root(setting)
      return [] unless dir.directory?

      cached("repos:#{dir}") do
        candidates =
          if dir.join(".git").exist?
            [dir]
          else
            dir.children.select { |c| c.directory? && c.join(".git").exist? }.sort
          end
        # stats shell out to git several times per repo — parallelize the I/O
        candidates.map { |path| Thread.new { stats(path) } }.map(&:value)
      rescue Errno::EACCES, Errno::ENOENT
        []
      end
    end

    def repo_names(setting = Setting.instance)
      repos(setting).map { |r| r[:name] }
    end

    # Folder listing for the wizard's chooser, annotated with what's inside.
    # [{ name:, rel:, kind: :git_repo | :repo_folder | :folder, repo_count: }, ...]
    def browse(setting = Setting.instance)
      dir = root(setting)
      return [] unless dir.directory?

      cached("browse:#{dir}") do
        dir.children
           .select(&:directory?)
           .reject { |c| c.basename.to_s.start_with?(".") || c.basename.to_s == "node_modules" }
           .sort.first(24).map do |child|
          nested = nested_repo_count(child)
          kind = if child.join(".git").exist? then :git_repo
                 elsif nested.positive? then :repo_folder
                 else :folder
                 end
          { name: child.basename.to_s, rel: child.relative_path_from(mount_root).to_s,
            kind: kind, repo_count: nested }
        end
      rescue Errno::EACCES, Errno::ENOENT
        []
      end
    end

    def parent_rel(setting = Setting.instance)
      dir = root(setting)
      return nil if dir == mount_root

      parent = dir.parent
      parent == mount_root ? "" : parent.relative_path_from(mount_root).to_s
    end

    # Sub-projects inside a repository (monorepo packages/apps/services…),
    # detected by common project markers. Relative paths, capped.
    def subprojects(repo_entry)
      cached("subs:#{repo_entry[:path]}", ttl: 300, allow_empty: true) do
        base = Pathname.new(repo_entry[:path])
        found = []
        base.children.select(&:directory?).sort.each do |child|
          name = child.basename.to_s
          next if name.start_with?(".") || name == "node_modules"

          if project_marker?(child)
            found << child.relative_path_from(base).to_s
          else
            child.children.select(&:directory?).sort.each do |grand|
              next if grand.basename.to_s.start_with?(".")

              found << grand.relative_path_from(base).to_s if project_marker?(grand)
            end
          end
          break if found.size >= 30
        end
        found.first(30)
      rescue Errno::EACCES, Errno::ENOENT
        []
      end
    end

    # Everything a ticket can target: each repo, plus "repo/sub/project"
    # entries for detected sub-projects.
    def ticket_targets(setting = Setting.instance)
      repos(setting).flat_map do |repo|
        [repo[:name]] + subprojects(repo).map { |sub| "#{repo[:name]}/#{sub}" }
      end
    end

    # Same, but honoring the wizard's repo selection — what the pipeline is
    # actually allowed to own.
    def selected_ticket_targets(setting = Setting.instance)
      selected_repos(setting).flat_map do |repo|
        [repo[:name]] + subprojects(repo).map { |sub| "#{repo[:name]}/#{sub}" }
      end
    end

    # Resolves a ticket's repo field ("core", "core · api", "mono/apps/web")
    # to the repository checkout path, or nil when not in the workspace.
    def repo_path(repo_field, setting = Setting.instance)
      return nil if repo_field.blank?

      wanted = repo_field.split("·").map { |t| t.strip.split("/").first }
      repos(setting).find { |r| wanted.include?(r[:name]) }&.dig(:path)
    end

    # The sub-project component of a ticket's repo field, if any.
    def subpath(repo_field)
      return nil if repo_field.blank?

      first = repo_field.split("·").first.to_s.strip
      sub = first.split("/", 2)[1]
      sub.presence
    end

    # Repos ticked in the setup wizard (all by default).
    def selected_repos(setting = Setting.instance)
      repos(setting).select { |r| setting.setup.fetch("repo:#{r[:name]}", "true") == "true" }
    end

    # Most recent commits across the selected repos, newest first — powers
    # the dashboard commits panel in live mode.
    def recent_commits(setting = Setting.instance, limit: 8)
      cached("commits:#{root(setting)}", ttl: 60) do
        selected_repos(setting).flat_map do |repo|
          out = git(Pathname.new(repo[:path]), "log", "-n", limit.to_s, "--pretty=%h%x09%ct%x09%s")
          next [] unless out

          out.lines.map do |line|
            sha, epoch, subject = line.chomp.split("\t", 3)
            CommitEntry.new(sha, subject.to_s, repo[:name], Time.zone.at(epoch.to_i))
          end
        end.sort_by.with_index { |c, i| [-c.committed_at.to_i, i] }.first(limit)
      end
    end

    # Names of workspace repos (selected or not) that contain openspec specs.
    def openspec_repos(setting = Setting.instance)
      cached("openspec:#{root(setting)}", allow_empty: true) do
        repos(setting).select { |r| Pathname.new(r[:path]).join("openspec", "specs").directory? }
                      .map { |r| r[:name] }
      end
    end

    private

    # allow_empty: cache [] as a valid result (e.g. a repo with no
    # sub-projects — rescanning it every render is exactly the cost we're
    # avoiding). Without it, empty scans are treated as transient mount
    # hiccups: never cached, last good value preferred.
    def cached(key, ttl: CACHE_TTL, allow_empty: false)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      CACHE_MUTEX.synchronize do
        @cache ||= {}
        entry = @cache[key]
        return entry[1] if entry && entry[0] > now
      end

      SCAN_LOCK.synchronize do
        # single-flight: whoever queued behind the scan reuses its result
        CACHE_MUTEX.synchronize do
          entry = @cache[key]
          return entry[1] if entry && entry[0] > now
        end

        value = yield
        if value.present? || allow_empty
          CACHE_MUTEX.synchronize { @cache[key] = [now + ttl, value] }
        else
          stale = CACHE_MUTEX.synchronize { @cache[key]&.last }
          return stale if stale.present?
        end
        value
      end
    end

    def project_marker?(dir)
      PROJECT_MARKERS.any? { |marker| dir.join(marker).exist? }
    end

    def nested_repo_count(dir)
      dir.children.count { |c| c.directory? && c.join(".git").exist? }
    rescue Errno::EACCES, Errno::ENOENT
      0
    end

    def stats(path)
      {
        name: repo_name(path),
        path: path.to_s,
        branch: git(path, "rev-parse", "--abbrev-ref", "HEAD") || "?",
        commits: git(path, "rev-list", "--count", "HEAD").to_i,
        files: git(path, "ls-files")&.lines&.size || 0
      }
    end

    # A repo mounted AS the root would otherwise be named "workspace" —
    # prefer the origin remote's name when the folder name is unhelpful.
    def repo_name(path)
      base = path.basename.to_s
      return base unless path == mount_root

      origin = git(path, "remote", "get-url", "origin")
      origin.present? ? File.basename(origin, ".git") : base
    end

    def git(path, *args)
      out, status = Open3.capture2("git", "-C", path.to_s, *args, err: File::NULL)
      status.success? ? out.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
