# Did the testing phase make the suite pass, or make it stop asking?
#
# The tester is told never to weaken, skip or delete a test to get a green
# run. Telling it is not checking it, and "make the tests pass" is the exact
# instruction under which deleting the failing test is the shortest path. This
# reads what actually changed under the test directories and says so.
#
# It reports rather than blocks: removing a test is legitimate when the ticket
# removes the feature. But the pull request stops looking green, which puts the
# decision in front of a person instead of past them.
module TestGuard
  # Paths a project keeps its tests in, across the conventions we are likely to
  # meet: rails/rspec, jest, pytest, go, and the language-agnostic dirs.
  TEST_PATH = %r{
    (\A|/)(tests?|spec|specs|__tests__|features)/ |
    (_test|_spec|\.test|\.spec)\.[a-z0-9]+\z |
    (\A|/)test_[^/]+\.py\z |
    (\A|/)conftest\.py\z
  }xi.freeze

  SKIP_MARKERS = {
    /\bxit\b|\bxdescribe\b|\bxcontext\b|\bxspecify\b/ => "rspec x-prefix",
    /\bskip\b\s*[("']|\bskip!\s*[("']|\bpending\b\s*[("']/ => "skip/pending",
    /@pytest\.mark\.skip|@unittest\.skip|pytest\.skip\(/ => "pytest skip",
    /\b(?:it|test|describe|context)\.skip\b/ => "js .skip",
    /\bt\.Skip(?:Now)?\(/ => "go t.Skip",
    /#\s*rubocop:disable\s+.*Lint/i => "lint disabled"
  }.freeze

  ASSERTION = /\b(assert\w*|expect|should_receive|must_equal|require\.\w+|EXPECT_\w+)\b/.freeze

  # A refactor moves assertions between files; a gutting removes them. Only
  # complain when a test file comes out meaningfully lighter than it went in.
  ASSERTION_SLACK = 2

  MAX_DIFF_LINES = 20_000

  module_function

  def test_path?(path) = TEST_PATH.match?(path.to_s)

  # [{kind:, path:, detail:}] — empty when the suite was left alone.
  def inspect_branch(repo, base, contract = nil)
    return [] if base.blank?

    tampered(repo, contract) + deleted(repo, base) + weakened(repo, base)
  end

  # The one check that cannot be talked around. Everything else here reads
  # intent out of a diff and can be argued with; a blob id either matches or
  # it does not, and planning recorded these before any code was written.
  def tampered(repo, contract)
    frozen = contract.is_a?(Hash) ? contract["frozen_tests"] : nil
    return [] unless frozen.is_a?(Hash)

    frozen.filter_map do |path, digest|
      now = PhaseRecord.current_digest(repo, path)
      next if now == digest

      { "kind" => "frozen", "path" => path,
        "detail" => now.nil? ? "a test frozen before the work began was deleted"
                             : "a test frozen before the work began was modified" }
    end
  end

  def deleted(repo, base)
    out, ok = GitRepo.capture(repo, "diff", "--name-only", "--diff-filter=D", "#{base}...HEAD")
    return [] unless ok

    out.lines.filter_map do |line|
      path = line.chomp
      next unless test_path?(path)

      { "kind" => "deleted", "path" => path, "detail" => "test file deleted" }
    end
  end

  def weakened(repo, base)
    out, ok = GitRepo.capture(repo, "diff", "--unified=0", "#{base}...HEAD")
    return [] unless ok

    flags = []
    counts = Hash.new { |h, k| h[k] = { added: 0, removed: 0 } }
    path = nil

    out.lines.first(MAX_DIFF_LINES).each do |raw|
      line = raw.chomp
      if line.start_with?("+++ ")
        path = line.delete_prefix("+++ ").sub(%r{\Ab/}, "").presence
        path = nil if path == "/dev/null" || !test_path?(path.to_s)
        next
      end
      next if path.nil? || line.start_with?("+++", "---", "@@", "diff ", "index ")

      if line.start_with?("+")
        counts[path][:added] += 1 if ASSERTION.match?(line)
        if (marker = SKIP_MARKERS.find { |pattern, _| pattern.match?(line) })
          flags << { "kind" => "skipped", "path" => path, "detail" => marker.last,
                     "line" => line.delete_prefix("+").strip.truncate(120) }
        end
      elsif line.start_with?("-")
        counts[path][:removed] += 1 if ASSERTION.match?(line)
      end
    end

    counts.each do |file, n|
      net = n[:removed] - n[:added]
      next if net <= ASSERTION_SLACK

      flags << { "kind" => "assertions", "path" => file,
                 "detail" => "#{net} more assertions removed than added" }
    end
    flags.uniq { |f| [f["kind"], f["path"], f["detail"]] }.first(20)
  end

  def summary(flags)
    return nil if flags.empty?

    by_kind = flags.group_by { |f| f["kind"] }
    parts = []
    parts << "#{by_kind['frozen'].size} frozen test(s) touched" if by_kind["frozen"]
    parts << "#{by_kind['deleted'].size} test file(s) deleted" if by_kind["deleted"]
    parts << "#{by_kind['skipped'].size} skip(s) added" if by_kind["skipped"]
    parts << "#{by_kind['assertions'].size} file(s) lost assertions" if by_kind["assertions"]
    parts.join(", ")
  end
end
