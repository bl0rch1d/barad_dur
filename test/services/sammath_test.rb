require "test_helper"

# Sammath is the harness shipped in the image. It is the default when a
# workspace brings none of its own, so the wiring between what the files
# declare and what the pipeline looks for has to actually line up — a skill
# named one thing and a candidate list expecting another fails silently by
# falling back to the built-in prompt.
class SammathTest < ActiveSupport::TestCase
  setup { @info = Harness.bundled }

  test "the bundled harness is found and knows what it is" do
    assert @info, "no harness at #{Harness.bundled_path.inspect}"
    assert @info.bundled?
    assert_match(/\ASammath \d+\.\d+\.\d+\z/, @info.label)
  end

  test "every phase maps to a skill — a missing one silently falls back to the built-in" do
    expected = { "investigation" => "/explore", "planning" => "/propose",
                 "implementation" => "/apply", "review" => "/review",
                 "testing" => "/test", "deployment" => "/ship" }

    expected.each do |phase, invocation|
      candidate = Harness::PHASE_CANDIDATES.fetch(phase).find { |c| Harness.provides?(@info, c) }
      assert_equal invocation, "/#{candidate}", "#{phase} does not resolve to a bundled skill"
    end
  end

  test "every agent a skill says it dispatches actually exists" do
    %w[scout review-unit review-verifier fixer].each do |agent|
      assert_includes @info.agents, agent
    end
  end

  test "the review phase is offered its own agents for delegation" do
    delegates = Harness::PHASE_AGENT_HINTS.fetch("review") & @info.agents

    assert_includes delegates, "review-unit"
    assert_includes delegates, "review-verifier"
    assert_includes delegates, "fixer"
  end

  test "every skill has frontmatter with a name matching its directory" do
    Dir.glob(File.join(Harness.bundled_path, ".claude/skills/*/SKILL.md")).each do |file|
      dir = File.basename(File.dirname(file))
      head = File.read(file, 400)

      assert_match(/\A---\n/, head, "#{dir}/SKILL.md has no frontmatter")
      assert_match(/^name:\s*#{Regexp.escape(dir)}\s*$/, head, "#{dir}/SKILL.md names something else")
      assert_match(/^description:\s*\S/, head, "#{dir}/SKILL.md has no description")
    end
  end

  test "every reference a skill points at is actually there" do
    Dir.glob(File.join(Harness.bundled_path, ".claude/skills/*/SKILL.md")).each do |file|
      body = File.read(file)
      body.scan(%r{`?references/([\w.-]+\.md)`?}).flatten.uniq.each do |reference|
        path = File.join(File.dirname(file), "references", reference)
        assert File.exist?(path), "#{File.basename(File.dirname(file))} points at a missing #{reference}"
      end
    end
  end

  test "every agent declares the tools it is allowed, and the read-only ones cannot write" do
    read_only = { "scout" => true, "review-unit" => false, "review-verifier" => false, "fixer" => false }

    read_only.each_key do |name|
      head = File.read(File.join(Harness.bundled_path, ".claude/agents/#{name}.md"), 500)
      assert_match(/^tools:\s*\S/, head, "#{name} declares no tools")
      next unless read_only[name]

      refute_match(/\b(Edit|Write|Bash)\b/, head[/^tools:.*$/].to_s,
                   "#{name} is meant to be read-only")
    end
  end

  test "the house rules cover the invariants the skills rely on" do
    rules = File.read(File.join(Harness.bundled_path, "CLAUDE.md"))

    assert_match(/BARAD-DUR-BRIEF/, rules, "every skill's step 1 depends on this")
    assert_match(/\$ARGUMENTS/, rules, "the one thing every source harness got wrong")
    assert_match(/-C <repo_path>/, rules, "the working directory is not the code")
    assert_match(/never.{0,40}(push|deploy)/im, rules)
    assert_match(/out_path/, rules, "a run that dies must still have reported")
  end

  test "running from the source checkout warns once, because it is inside a repo" do
    Harness.instance_variable_set(:@warned_source_checkout, nil)
    Event.where(meta: "harness").delete_all

    3.times { Harness.bundled_path }

    if Harness.bundled_path == Rails.root.join("harness").to_s
      assert_equal 1, Event.where(meta: "harness").count, "once, not once per call"
      assert_match(/commit into barad-dûr itself/, Event.where(meta: "harness").last.text)
    else
      assert_equal 0, Event.where(meta: "harness").count,
                    "the image path is outside a repo and needs no warning"
    end
  end

  test "a workspace harness still wins over the bundled one" do
    # Harness.detect prefers a scanned workspace repo; bundled is the fallback.
    source = File.read(Rails.root.join("app/services/harness.rb"))
    detect = source[/def detect.*?^    end/m]

    assert_match(/repos\.filter_map.*\|\|\s*\n\s*bundled/m, detect,
                 "the workspace's own conventions must outrank the default")
  end
end
