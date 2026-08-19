require "json"

# What this repository can actually be verified with.
#
# The testing phase used to rediscover this every run — read package.json, read
# the Rakefile, guess — which costs turns on work that is the same every time
# and, when the turns run short, ends in "no suite ran". A handful of file
# reads in Ruby answers it for free, and answering it here means the tower also
# knows what *should* have run, so an agent that quietly skipped the linter can
# be caught rather than believed.
#
# It is a starting point, not an authority: the prompt tells the agent to
# correct it when it is wrong, because a detected command still has to work.
module Toolchain
  Command = Struct.new(:kind, :command, :because, keyword_init: true)

  module_function

  # [Command] ordered lint → unit → e2e, which is the order they should run in.
  def detect(repo)
    return [] if repo.blank? || !File.directory?(repo.to_s)

    found = ruby(repo) + node(repo) + python(repo) + go(repo) + rust(repo) + make(repo)
    order = { "lint" => 0, "unit" => 1, "e2e" => 2 }
    found.uniq { |c| c.command }.sort_by { |c| order.fetch(c.kind, 3) }
  end

  def describe(repo)
    commands = detect(repo)
    return nil if commands.empty?

    lines = commands.map { |c| "  - #{c.kind}: `#{c.command}`  (#{c.because})" }
    <<~TXT
      This repository appears to be verifiable with:
      #{lines.join("\n")}

      That list was read off the repository's own configuration, not guessed —
      but it has not been run. Correct it where it is wrong, add what it missed,
      and say so in your report. A command that does not exist is worth saying
      out loud; silently running nothing is not.
    TXT
  end

  # ── per ecosystem ──────────────────────────────────────────────────────

  def ruby(repo)
    return [] unless exist?(repo, "Gemfile")

    out = []
    lock = read(repo, "Gemfile.lock").to_s
    if dir?(repo, "spec")
      out << Command.new(kind: "unit", command: "bundle exec rspec", because: "spec/ and a Gemfile")
    elsif dir?(repo, "test")
      runner = exist?(repo, "bin/rails") ? "bin/rails test" : "bundle exec rake test"
      out << Command.new(kind: "unit", command: runner, because: "test/ and a Gemfile")
    end
    out << Command.new(kind: "lint", command: "bundle exec rubocop", because: "rubocop in the bundle") if
      lock.include?("rubocop") || exist?(repo, ".rubocop.yml")
    out << Command.new(kind: "e2e", command: "bin/rails test:system", because: "test/system/") if
      dir?(repo, "test/system")
    out
  end

  def node(repo)
    raw = read(repo, "package.json") or return []

    scripts = JSON.parse(raw)["scripts"].to_h
    runner = exist?(repo, "pnpm-lock.yaml") ? "pnpm" : exist?(repo, "yarn.lock") ? "yarn" : "npm run"
    mapping = { "unit" => %w[test test:unit jest vitest],
                "lint" => %w[lint lint:js typecheck tsc],
                "e2e" => %w[e2e test:e2e cypress playwright] }

    mapping.flat_map do |kind, names|
      name = names.find { |n| scripts.key?(n) } or next []
      [Command.new(kind: kind, command: "#{runner} #{name}", because: "the \"#{name}\" script in package.json")]
    end
  rescue JSON::ParserError
    []
  end

  def python(repo)
    project = read(repo, "pyproject.toml").to_s
    has_pytest = exist?(repo, "pytest.ini") || exist?(repo, "tox.ini") ||
                 project.include?("pytest") || dir?(repo, "tests")
    out = []
    out << Command.new(kind: "unit", command: "pytest", because: "a pytest configuration") if has_pytest
    out << Command.new(kind: "lint", command: "ruff check .", because: "ruff in pyproject.toml") if
      project.include?("ruff") || exist?(repo, "ruff.toml")
    out << Command.new(kind: "lint", command: "flake8", because: ".flake8") if exist?(repo, ".flake8")
    out
  end

  def go(repo)
    return [] unless exist?(repo, "go.mod")

    out = [Command.new(kind: "unit", command: "go test ./...", because: "go.mod")]
    out << Command.new(kind: "lint", command: "golangci-lint run", because: ".golangci.yml") if
      exist?(repo, ".golangci.yml") || exist?(repo, ".golangci.yaml")
    out
  end

  def rust(repo)
    return [] unless exist?(repo, "Cargo.toml")

    [Command.new(kind: "unit", command: "cargo test", because: "Cargo.toml"),
     Command.new(kind: "lint", command: "cargo clippy -- -D warnings", because: "Cargo.toml")]
  end

  # A Makefile target beats a guessed command: someone wrote it on purpose.
  def make(repo)
    body = read(repo, "Makefile") or return []

    targets = body.scan(/^([a-zA-Z][\w.-]*):/).flatten
    { "lint" => %w[lint fmt-check], "unit" => %w[test tests check], "e2e" => %w[e2e integration] }
      .flat_map do |kind, names|
        name = names.find { |n| targets.include?(n) } or next []
        [Command.new(kind: kind, command: "make #{name}", because: "the #{name} target in the Makefile")]
      end
  end

  # ── file helpers ───────────────────────────────────────────────────────

  def exist?(repo, path) = File.exist?(File.join(repo.to_s, path))
  def dir?(repo, path) = File.directory?(File.join(repo.to_s, path))

  def read(repo, path)
    full = File.join(repo.to_s, path)
    File.read(full, 200_000) if File.file?(full)
  rescue SystemCallError
    nil
  end
end
