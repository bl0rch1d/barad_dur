# Detects a custom agentic harness inside the workspace: Claude Code
# commands (.claude/commands/**/*.md), skills (.claude/skills/*) and agents
# (.claude/agents/*.md). When present (and the framework isn't "vanilla"),
# pipeline phases and the RFC flow invoke the harness's own commands instead
# of the built-in prompts, executing inside the harness repo with the whole
# workspace reachable via --add-dir.
class Harness
  Info = Struct.new(:repo, :path, :commands, :skills, :agents, :agent_details, keyword_init: true)

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
    "investigation" => %w[explorer scout],
    "planning"      => %w[planner critic],
    "review"        => %w[reviewer review-unit review-integration review-verifier critic]
  }.freeze

  class << self
    def detect(setting = Setting.instance)
      Workspace.memo("harness:#{Workspace.root(setting)}") do
        Workspace.repos(setting).filter_map { |repo| scan(repo) }.first
      end
    end

    def active?(setting = Setting.instance)
      setting.setup["fw"] != "2" && detect(setting).present?
    end

    # "/opsx:explore"-style invocation for a phase, or nil for built-in.
    # setup["map:<phase>"] overrides: "built-in" forces built-in, "harness"
    # (or absence) resolves through the candidates.
    def phase_invocation(phase, setting = Setting.instance)
      return nil unless active?(setting)
      return nil if setting.setup["map:#{phase}"] == "built-in"

      default_invocation(phase, setting)
    end

    # The invocation the candidates would resolve to, ignoring overrides.
    def default_invocation(phase, setting = Setting.instance)
      info = detect(setting)
      return nil unless info

      PHASE_CANDIDATES.fetch(phase, []).each do |candidate|
        return "/#{candidate}" if provides?(info, candidate)
      end
      nil
    end

    def phase_agents(phase, setting = Setting.instance)
      info = detect(setting)
      return [] unless info

      PHASE_AGENT_HINTS.fetch(phase, []).select { |name| info.agents.include?(name) }
    end

    def provides?(info, name)
      info.commands.include?(name) || info.skills.include?(name)
    end

    private

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
