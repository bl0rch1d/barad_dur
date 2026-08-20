# Detects a custom agentic harness inside the workspace: Claude Code
# commands (.claude/commands/**/*.md), skills (.claude/skills/*) and agents
# (.claude/agents/*.md). When present (and the framework isn't "vanilla"),
# pipeline phases and the RFC flow invoke the harness's own commands instead
# of the built-in prompts, executing inside the harness repo with the whole
# workspace reachable via --add-dir.
class Harness
  Info = Struct.new(:repo, :path, :commands, :skills, :agents, :agent_details, :bundled,
                    keyword_init: true) do
    def bundled? = bundled == true
    def label = bundled? ? "Sammath #{Harness.bundled_version}" : repo
  end

  # Shipped inside the image, used when the workspace has no harness of its
  # own. It is the default, not a fallback of last resort: the built-in
  # prompts stay reachable per phase, and a realm that wants none of it sets
  # the framework to vanilla.
  BUNDLED_NAME = "sammath".freeze

  # The wizard value that means "use the bundled one even though the workspace
  # has its own". A leading colon cannot be a real path under the mount, so it
  # can never collide with a directory someone actually has.
  BUNDLED_CHOICE = ":bundled".freeze

  # Candidates tried in order per phase; a candidate matches a command or a
  # skill of that name. Phases with no match use the built-in prompts.
  PHASE_CANDIDATES = {
    "investigation"  => %w[opsx:explore explore research],
    "planning"       => %w[opsx:propose propose],
    "implementation" => %w[opsx:apply apply],
    "review"         => %w[opsx:review review],
    "testing"        => %w[opsx:test test],
    "deployment"     => %w[opsx:ship ship deploy]
  }.freeze

  # Project agents suggested for delegation per phase, when they exist.
  PHASE_AGENT_HINTS = {
    "investigation"  => %w[explorer scout researcher],
    "planning"       => %w[planner architect critic],
    "implementation" => %w[builder fixer backend-dev frontend-dev],
    "review"         => %w[reviewer review-unit review-integration review-verifier critic fixer],
    "testing"        => %w[tester test-runner qa],
    "deployment"     => %w[shipper release-manager]
  }.freeze

  class << self
    # A directory picked in the wizard wins; otherwise the first selected repo
    # that has one. Auto-detection stays restricted to selected repos — an
    # unchecked repo must not drive the pipeline by accident — but an explicit
    # choice may point anywhere in the mount, since that is consent.
    # Both the selection and the choice are in the memo key, so switching in
    # the wizard takes effect immediately.
    def detect(setting = Setting.instance)
      repos = Workspace.selected_repos(setting)
      chosen = setting.setup["harness_dir"].to_s
      key = "harness:#{Workspace.root(setting)}:#{chosen}:#{repos.map { |r| r[:name] }.join(',')}"

      Workspace.memo(key) do
        (chosen.present? && scan_path(chosen, setting)) ||
          repos.filter_map { |repo| scan(repo) }.first ||
          bundled
      end
    end

    # The harness that ships with the image. HARNESS_DIR wins so a deployment
    # can mount its own; the image path is next; Rails.root is the development
    # checkout, where harness/ is source rather than a copy.
    def bundled
      path = bundled_path or return nil

      info = scan({ name: BUNDLED_NAME, path: path })
      info&.tap { |i| i.bundled = true }
    end

    def bundled_path
      path = [ENV["HARNESS_DIR"].presence, "/opt/barad-dur/harness", Rails.root.join("harness").to_s]
             .compact.find { |dir| File.directory?(File.join(dir, ".claude", "skills")) }
      warn_about_source_checkout(path) if path == Rails.root.join("harness").to_s
      path
    end

    # In the image the harness sits at /opt, outside any git repository, so a
    # phase whose git command forgot its -C fails loudly. The development
    # fallback is the source tree, which IS a repository — the same mistake
    # there stages into barad-dûr's own checkout instead. Say so once.
    def warn_about_source_checkout(path)
      return if @warned_source_checkout

      @warned_source_checkout = true
      Event.record!(phase_tag: "SYS", tone: "var(--warn)", agent_name: "system", meta: "harness",
                    text: "Running the harness from the source tree at #{path} — it is inside a git " \
                          "repository, so a phase that forgets -C can commit into barad-dûr itself. " \
                          "The built image keeps it at /opt/barad-dur/harness, outside one.")
    rescue StandardError
      nil
    end

    def bundled_version
      path = bundled_path or return "?"

      File.read(File.join(path, "VERSION"), 32).to_s.strip.presence || "?"
    rescue SystemCallError
      "?"
    end

    # Every directory in the mount that carries a harness: the workspace root
    # itself and each folder one level down. Used by the wizard to offer a
    # choice rather than only announcing what was found first.
    def available(setting = Setting.instance)
      root = Workspace.root(setting)
      return [] unless root.directory?

      selected = Workspace.selected_repos(setting).map { |r| r[:name] }
      Workspace.memo("harness-choices:#{root}", ttl: 120, allow_empty: true) do
        # the root, each repo, and each repo's immediate sub-projects — enough
        # to reach a monorepo package without walking the whole tree
        tops = root.children.select { |c| interesting?(c) }.sort
        dirs = [root] + tops + tops.flat_map { |top| top.children.select { |c| interesting?(c) }.sort }
        dirs.first(200).filter_map do |dir|
          info = scan({ name: dir.basename.to_s, path: dir.to_s })
          next unless info

          rel = dir == root ? "." : dir.relative_path_from(root).to_s
          { name: info.repo, rel: rel, commands: info.commands.size,
            skills: info.skills.size, agents: info.agents.size,
            selected: selected.include?(info.repo) }
        end
      rescue Errno::EACCES, Errno::ENOENT
        []
      end
    end

    # Resolves a wizard-chosen directory, relative to the workspace root.
    # Never escapes the mount.
    def scan_path(rel, setting = Setting.instance)
      return bundled if rel == BUNDLED_CHOICE

      root = Workspace.root(setting)
      dir = rel == "." ? root : (root + rel).cleanpath
      return nil unless dir.to_s.start_with?(root.to_s) && dir.directory?

      scan({ name: dir.basename.to_s, path: dir.to_s })
    end

    # A harness is always in force now that one ships with the app. Opting a
    # phase out is per phase (setup["map:<phase>"] == "built-in"), which is a
    # real choice; there is no longer a global switch that silently turns six
    # phases into three-line prompts. Legacy "vanilla" realms are reinterpreted
    # once at boot, with an Event, rather than being quietly overridden.
    def active?(setting = Setting.instance)
      detect(setting).present?
    end

    # [invocation, info] — the harness in force for THIS phase.
    #
    # The primary harness is tried first (an explicit choice, else the first
    # selected repo that has one), and the bundled harness is the per-phase
    # backstop. Resolution used to be wholesale: a repo whose .claude covered
    # four phases left the other two on the built-in prompts, which is the
    # worst of both — your conventions for some phases and a three-line prompt
    # for the rest.
    def source_for(phase, setting = Setting.instance)
      return [nil, nil] if setting.setup["map:#{phase}"] == "built-in"

      primary = detect(setting)
      if primary && (name = candidate_for(primary, phase))
        return ["/#{name}", primary]
      end
      # Already the bundled one: there is nothing further to fall back to.
      return [nil, nil] if primary.nil? || primary.bundled?

      backstop = bundled
      name = backstop && candidate_for(backstop, phase)
      name ? ["/#{name}", backstop] : [nil, nil]
    end

    # "/opsx:explore"-style invocation for a phase, or nil for built-in.
    def phase_invocation(phase, setting = Setting.instance)
      source_for(phase, setting).first
    end

    # What would resolve if the phase were not overridden — the wizard shows
    # this so an override reads as a choice rather than as an absence.
    def default_invocation(phase, setting = Setting.instance)
      source_for(phase, setting.dup.tap { |s| s.setup = s.setup.except("map:#{phase}") }).first
    end

    def candidate_for(info, phase)
      PHASE_CANDIDATES.fetch(phase, []).find { |candidate| provides?(info, candidate) }
    end

    # Delegates come from whichever harness actually staffs this phase, not
    # from the primary one — a bundled-backstop phase must offer the bundled
    # agents, which are the only ones its skill knows how to prompt.
    def phase_agents(phase, setting = Setting.instance)
      info = source_for(phase, setting).last || detect(setting)
      return [] unless info

      PHASE_AGENT_HINTS.fetch(phase, []).select { |name| info.agents.include?(name) }
    end

    def provides?(info, name)
      info.commands.include?(name) || info.skills.include?(name)
    end

    SKIP_DIRS = %w[node_modules vendor tmp log .git dist build target coverage].freeze

    def interesting?(dir)
      name = dir.basename.to_s
      dir.directory? && !name.start_with?(".") && !SKIP_DIRS.include?(name)
    rescue Errno::EACCES, Errno::ENOENT
      false
    end

    def scan(repo)
      base = Pathname.new(repo[:path]).join(".claude")
      return nil unless base.directory?

      commands = Dir.glob(base.join("commands", "**", "*.md")).map do |file|
        Pathname.new(file).relative_path_from(base.join("commands")).to_s.delete_suffix(".md").tr("/", ":")
      end.sort
      skills = base.join("skills").then do |dir|
        dir.directory? ? dir.children.select(&:directory?).map { |c| c.basename.to_s }.sort : []
      end
      agent_details = Dir.glob(base.join("agents", "*.md")).sort.map do |file|
        # byte-limited File.read returns BINARY — force UTF-8 or ERB blows up
        head = File.read(file, 2048).to_s.force_encoding(Encoding::UTF_8).scrub
        { name: File.basename(file, ".md"),
          description: head[/^description:\s*(.+)$/, 1].to_s.strip.truncate(220) }
      end

      return nil if commands.empty? && skills.empty?

      Info.new(repo: repo[:name], path: repo[:path], commands: commands, skills: skills,
               agents: agent_details.map { |a| a[:name] }, agent_details: agent_details)
    end
  end
end
