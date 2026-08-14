# Parses openspec capability specs out of the workspace repos into the
# Capability / SpecRequirement / SpecScenario tables.
#
# Expected layout per repo (the openspec convention):
#   openspec/specs/<capability>/spec.md
# with markdown sections:
#   ## Purpose
#   ## Requirements
#   ### Requirement: <name>
#   <requirement text (SHALL/MUST...)>
#   #### Scenario: <name>
#   - GIVEN / WHEN / THEN lines
class SpecSync
  Parsed = Struct.new(:slug, :file, :title, :purpose, :repo, :reqs)
  ParsedReq = Struct.new(:name, :body, :scenarios)

  class << self
    # Parses all selected repos' specs. The optional progress callback receives
    # (done, total, label) after each capability — the async SpecSyncJob uses
    # it to drive the wizard's live progress bar.
    def call(setting = Setting.instance, progress: nil)
      targets = spec_targets(setting)
      total = targets.size
      parsed = targets.each_with_index.filter_map do |(repo, cap_dir, file), index|
        result = parse_file(file, cap_dir.basename.to_s, repo[:name])
        progress&.call(index + 1, total, "#{repo[:name]}/#{cap_dir.basename}")
        result
      end

      if parsed.empty?
        Event.record!(phase_tag: "SPEC", tone: "var(--warn)", agent_name: "Scout",
                      meta: "openspec/specs", text: "Spec parse found no openspec capabilities in the selected repos")
        return 0
      end

      Capability.transaction do
        Capability.destroy_all
        parsed.each_with_index { |spec, i| persist(spec, i) }
      end
      Event.record!(phase_tag: "SPEC", agent_name: "Scout",
                    text: "Parsed #{parsed.size} openspec capabilities from the workspace",
                    meta: "#{parsed.sum { |s| s.reqs.size }} requirements")
      parsed.size
    end

    # Human-readable outcome for the wizard, explaining zero-result parses.
    def status_summary(setting, count)
      if count.positive?
        return "✓ all #{count} spec #{'file'.pluralize(count)} parsed · #{SpecRequirement.count} requirements · #{Time.current.strftime('%H:%M')}"
      end

      with_specs = Workspace.openspec_repos(setting)
      unchecked = with_specs - Workspace.selected_repos(setting).map { |r| r[:name] }
      if unchecked.any?
        "nothing parsed — #{unchecked.join(', ')} contains openspec specs but is unchecked in the Folder step"
      elsif with_specs.empty?
        "nothing found — expected <repo>/openspec/specs/<capability>/spec.md"
      else
        "nothing parsed from the selected repos"
      end
    end

    # [[repo_entry, capability_dir, spec_file], ...] across selected repos.
    def spec_targets(setting)
      Workspace.selected_repos(setting).flat_map do |repo|
        dir = Pathname.new(repo[:path]).join("openspec", "specs")
        next [] unless dir.directory?

        dir.children.select(&:directory?).sort.filter_map do |cap_dir|
          file = cap_dir.join("spec.md")
          [repo, cap_dir, file] if file.file?
        end
      end
    end

    def parse_file(file, cap_name, repo_name)
      purpose = nil
      reqs = []
      section = nil

      file.read.each_line do |raw|
        line = raw.chomp
        case line
        when /\A##\s+Purpose\s*\z/ then section = :purpose
        when /\A###\s+Requirement:\s*(.+)\z/
          section = :req
          reqs << ParsedReq.new(Regexp.last_match(1).strip, +"", [])
        when /\A####\s+Scenario:\s*(.+)\z/
          section = :scenario
          reqs.last&.scenarios&.push({ name: "Scenario · #{Regexp.last_match(1).strip}", body: +"" })
        when /\A#{'#'}\s/, /\A##\s/ then section = nil
        else
          text = line.rstrip
          case section
          when :purpose  then purpose = [purpose, text.strip].compact.reject(&:empty?).join(" ")
          when :req      then reqs.last.body << text << "\n" unless text.empty? && reqs.last.body.empty?
          when :scenario
            scenario = reqs.last&.scenarios&.last
            scenario[:body] << text.sub(/\A[-*]\s*/, "").gsub("**", "") << "\n" if scenario && !text.empty?
          end
        end
      end

      title = cap_name.tr("-_", " ").capitalize
      Parsed.new("#{repo_name}/#{cap_name}", file.to_s.sub(%r{\A/workspace/}, ""),
                 title, purpose || "No purpose section.", repo_name, reqs)
    end

    private

    def persist(spec, position)
      capability = Capability.create!(
        slug: spec.slug, file: spec.file, title: spec.title, purpose: spec.purpose,
        meta_label: "#{spec.reqs.size} reqs · #{spec.repo}",
        tags: ["repo: #{spec.repo}", "synced #{Time.current.strftime('%H:%M')}"],
        position: position
      )
      spec.reqs.each_with_index do |req, i|
        record = capability.spec_requirements.create!(
          rid: "R-#{i + 1}", name: req.name, status: "specced",
          body: req.body.strip, impl_ref: spec.repo, tests_label: "#{req.scenarios.size} scenarios",
          position: i
        )
        req.scenarios.each_with_index do |scenario, j|
          record.spec_scenarios.create!(name: scenario[:name], body: scenario[:body].strip, position: j)
        end
      end
    end
  end
end
