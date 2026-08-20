# The record a ticket's phases write to each other: one markdown file, seven
# headings, one owner each.
#
#   ## Intent        investigation — what the change is FOR
#   ## Findings      investigation — where the code is, what it touches
#   ## Plan          planning      — the ordered steps
#   ## Changes       implementation— what was actually done
#   ## Review        review        — what the critic found
#   ## Verification  testing       — what was run and what it proved
#   ## Ship          deployment    — the release note
#
# Ruby parses it rather than asking the next phase to cope. Where a design
# leaves "if the previous section is missing, do a compressed version and say
# so" as an instruction to the next model, that instruction is followed only
# when the model feels like it. Here the missing section is computed, named in
# the brief, and — for the two phases that cannot honestly proceed without one
# — fails the run instead.
module PhaseRecord
  HEADINGS = %w[Intent Findings Plan Changes Review Verification Ship].freeze

  OWNER = { "investigation" => %w[Intent Findings], "planning" => %w[Plan],
            "implementation" => %w[Changes], "review" => %w[Review],
            "testing" => %w[Verification], "deployment" => %w[Ship] }.freeze

  # What each phase needs from the phases before it. Absence is reported, not
  # assumed away.
  REQUIRES = { "planning" => %w[Intent], "implementation" => %w[Intent Plan],
               "review" => %w[Intent Changes], "testing" => %w[Changes],
               "deployment" => %w[Changes] }.freeze

  # A phase that cannot be done honestly on a hole. Investigation's findings
  # can be re-derived; a plan invented without an intent cannot.
  MUST_HAVE = %w[planning implementation].freeze

  OWNER_OF = OWNER.flat_map { |phase, sections| sections.map { |s| [s.downcase, phase] } }.to_h.freeze

  module_function

  def dir(repo, code) = File.join(repo.to_s, ".pipe", code.to_s.upcase)
  def path(repo, code) = File.join(dir(repo, code), "record.md")
  def contract_path(repo, code) = File.join(dir(repo, code), "contract.json")
  def out_path(repo, code, phase) = File.join(dir(repo, code), "#{phase}.out.json")

  # { "Intent" => "…" } for headings that exist AND have content under them.
  def sections(repo, code)
    body = read(repo, code) or return {}

    found = {}
    current = nil
    body.each_line do |line|
      if (heading = line[/\A##\s+(\w+)\s*\z/, 1]) && HEADINGS.include?(heading)
        current = heading
        found[current] = +""
      elsif current
        found[current] << line
      end
    end
    found.transform_values(&:strip).reject { |_, text| text.empty? }
  end

  # Downcased names of the sections this phase wanted and did not get.
  def degraded(repo, code, phase)
    wanted = REQUIRES.fetch(phase, [])
    return [] if wanted.empty?

    (wanted - sections(repo, code).keys).map(&:downcase)
  end

  def blocking?(phase, degraded) = MUST_HAVE.include?(phase) && degraded.any?

  def owner_of(section) = OWNER_OF[section.to_s.downcase]

  # Creates the file with all seven headings so every phase writes into a
  # shape it did not have to invent. Never overwrites.
  def ensure!(repo, code)
    file = path(repo, code)
    return file if File.exist?(file)

    FileUtils.mkdir_p(dir(repo, code))
    body = ["# #{code.to_s.upcase}", ""] + HEADINGS.flat_map { |h| ["## #{h}", ""] }
    File.write(file, body.join("\n"))
    write_gitignore(repo)
    file
  rescue SystemCallError
    nil
  end

  # The brief and the out-files are machine scratch: they carry no history and
  # would churn every diff. The record itself is committed on purpose.
  def write_gitignore(repo)
    file = File.join(repo.to_s, ".pipe", ".gitignore")
    return if File.exist?(file)

    File.write(file, "*.brief.json\n*.out.json\n")
  rescue SystemCallError
    nil
  end

  def read(repo, code)
    File.read(path(repo, code), 200_000).to_s.force_encoding(Encoding::UTF_8).scrub
  rescue SystemCallError
    nil
  end

  # Ruby writes the frozen contract rather than trusting a phase to.
  #
  # It is the anchor for per-criterion conformance in review, per-criterion
  # verification in testing, and the tamper check afterwards — so the two
  # fields that must not be wrong (the base commit and the digests of every
  # test that already existed) are computed here, where they cannot be
  # mistyped, guessed, or reported optimistically.
  def freeze!(repo, code, criteria:, base_sha:, impact: [], risk: {}, existing: nil)
    contract = {
      "_v" => 1, "code" => code.to_s.upcase, "base_sha" => base_sha,
      "criteria" => criteria.each_with_index.map { |text, i| { "id" => i + 1, "text" => text.to_s } },
      "impact" => Array(impact).map(&:to_s).first(200),
      "frozen_tests" => frozen_tests(repo, base_sha),
      "risk" => risk
    }
    contract = (existing || {}).merge(contract) if existing
    FileUtils.mkdir_p(dir(repo, code))
    File.write(contract_path(repo, code), JSON.pretty_generate(contract))
    contract
  rescue SystemCallError, JSON::GeneratorError
    nil
  end

  # Every test file that already existed at the base commit, with its blob id.
  # `git rev-parse <sha>:<path>` is the id git already stored, so this costs
  # one call and cannot disagree with what git thinks the file was.
  def frozen_tests(repo, base_sha)
    return {} if base_sha.blank?

    out, ok = GitRepo.capture(repo, "ls-tree", "-r", "--name-only", base_sha)
    return {} unless ok

    out.lines.map(&:chomp).select { |path| TestGuard.test_path?(path) }.first(500).to_h do |path|
      oid, found = GitRepo.capture(repo, "rev-parse", "#{base_sha}:#{path}")
      [path, found ? oid.strip : nil]
    end.compact
  end

  # What that path hashes to now — nil when it is gone.
  def current_digest(repo, path)
    full = File.join(repo.to_s, path)
    return nil unless File.file?(full)

    out, ok = GitRepo.capture(repo, "hash-object", "--", path)
    ok ? out.strip.presence : nil
  end

  def contract(repo, code)
    JSON.parse(File.read(contract_path(repo, code), 500_000))
  rescue SystemCallError, JSON::ParserError
    nil
  end
end
