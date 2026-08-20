# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The daily spend cap is set during setup, on the auth step, rather than only
  afterwards — it is the one number worth deciding before agents can spend
  anything.
- A **Done** column on the board, where merged work lands. It shows the most
  recent landings with when they landed, their cost and a link to the pull
  request, and points at the full shipped history beyond that.
- A **Settings** screen, scoped to the bound realm: how work lands, which phases
  run, the orchestrator model, the daily cap and autonomy — none of which
  previously survived the setup wizard.
- Work stops after the last enabled phase and waits on a verdict gate instead of
  marking itself shipped. Approving lands it the way the realm was configured to.
- A pull request opens automatically once that point is reached, and the ticket
  carries its link.
- **Every agent can run on its own model.** Click an agent card to open a
  configuration panel explaining what the role does, which phase it serves,
  which command or prompt it runs, what it can delegate to, and what it has
  cost. An agent follows the realm's orchestrator setting until you pin it, so
  changing that still moves everything you have not overridden.
- **Review produces a verdict, not prose.** Each finding is blocking or minor;
  a blocking one sends the ticket back to implementation with the finding
  attached, at most twice, after which the unresolved findings are carried to
  your verdict rather than looping. They appear in the ticket drawer under
  **Review findings**, with the blocking ones flagged.
- A phase writes its structured answer to a file as well as to its final
  message, so a run killed at the turn limit or the timeout still reports what
  it found.

### Changed

- The testing phase is the last automated gate before a human sees the work,
  so it now runs everything the project has — linters and formatters, unit
  tests, regression and integration suites, and end-to-end tests — reports
  each separately, and says plainly when one could not run rather than
  skipping it silently. It is told never to weaken or delete a test to make
  it pass.
- A pull request whose suite is red opens as a **draft**, titled
  "[tests failing]", so the work is visible without looking ready to merge.
- **Deployment is off by default.** It only appends a changelog entry, and
  leaving it on meant tickets reached "done" unattended. Its board column is
  visibly disabled and links to the setting.
- Approving a ticket merges its pull request by default, rather than merging
  into the local default branch.
- A phase's structured result is found by its own sentinel rather than by
  taking the last fenced JSON block in the message. A review report is mostly
  code fences, and the last one is very often an example the agent was
  explaining rather than the contract it was asked for.
- **The Critic reports problems and no longer fixes them.** A reviewer that
  edits the code is, on the next round, reviewing its own work — and an agent
  almost never rejects its own fix.

### Fixed

- The setup wizard's indexing card no longer claims the workspace is indexed
  while the spec parse is still running. It eased a cosmetic bar to 100% in
  about ten seconds and unlocked Continue, whatever the real parse was doing —
  a 65-file workspace takes over a minute. While a parse runs the card shows
  its actual position, names the file being read, and Continue stays locked
  until the job finishes.
- A ticket waiting on your verdict no longer releases the tickets that depend on
  it. The dependency rule was always right — it was being told the parent was
  done, because the pipeline completed it without asking.
- **Phases after planning are given the specification.** The acceptance
  criteria, the planner's technical notes and the description never reached
  implementation, review or testing, so each phase re-derived the goal from the
  code it was meant to be judging.
- **Answers to clarifying questions now reach the agents.** `chosen` was written
  when you answered and read nowhere: the pipeline asked, parked the ticket,
  resumed on your answer, and no prompt ever learned what you decided.
- **A failed run keeps what it produced.** Commits, the diff, clarification
  questions and test results were all discarded when a run died — and that is
  exactly the run that had done the most work, so the retry started from
  nothing and the money was spent twice.
- A harness-mapped phase is told the path of the repository under work. It runs
  from the harness repo, so every bare git command it issued operated on the
  wrong checkout.
- A repo where no suite could run no longer reads as green. It recorded nothing,
  `tests_failed?` stayed false, and a non-draft pull request opened on
  unverified work; such a pull request is now a draft titled "[unverified]".
- The work branch is created once and only ever checked out again. `checkout -B`
  reset it to whatever HEAD held, so retrying after a merge conflict — which
  leaves HEAD on the base branch — silently discarded every implementation
  commit. It is also prepared for review, testing and deployment, not only
  implementation.
- **Sammath, a six-skill harness, ships with the app and is the default when a
  repository has none of its own.** `/explore` grounds the ticket in the code
  and writes what the change is *for*; `/propose` freezes acceptance criteria
  and a contract before any code exists; `/apply` commits the test before the
  fix; `/review` dispatches bounded units, executes before it opines, and then
  tries to *refute* its own findings before reporting them; `/test` verifies
  each criterion by name; `/ship` checks hygiene against what the repository
  actually has. Four subagents come with it — a read-only scout, a per-unit
  reviewer, an adversarial verifier, and a fixer that never sees who raised the
  finding it is fixing. A repository with its own `.claude` skills still wins,
  and the wizard can now pick Sammath explicitly over one.
- **Every phase is handed a brief that Ruby computed.** The resolved base
  commit, the runnable toolchain, untruncated acceptance criteria, the answers
  you gave to clarifying questions, the repository's own `CLAUDE.md` — which
  never auto-loads for a harness phase — and, named explicitly, whichever
  upstream section is missing. Planning and implementation refuse to start on a
  gap that an earlier phase ran and failed to fill, rather than inventing what
  should have been there.
- Phases now carry their own turn and time budgets rather than sharing one
  ceiling set for the longest of them. Review gets the headroom it needs to fan
  out; deployment no longer carries a budget it could never use.
- **The testing phase is told how to verify the project instead of working it
  out again every run.** The repository's own configuration — Gemfile,
  package.json scripts, pyproject, go.mod, Cargo.toml, Makefile targets — is
  read in a few file reads and handed over as a starting point it is asked to
  correct. Rediscovering it cost turns on an answer that never changes, and
  when the turns ran short the phase finished having verified nothing. It also
  means the tower knows what the repo has, so a suite that came back neither
  run nor explained is now called out.
- **A green run that asks less is no longer taken for a green run.** The tester
  is told never to weaken, skip or delete a test to make the suite pass, and
  nothing checked — while "make the tests pass" is the exact instruction under
  which deleting the failing test is the shortest path. The branch is now read
  for deleted test files, added skip markers and gutted assertions across the
  rspec, jest, pytest and go conventions. Removing a test is fair when the
  ticket removes the feature, so this reports rather than blocks: the ticket
  says what changed, the pull request stays a draft titled "[suite weakened]",
  and you decide.
- The pull request body now carries its own verification story — what ran, what
  passed, what could not run and why, and any weakening — since whoever reviews
  it on GitHub cannot see the tower.
- **A phase can no longer burn a fortune inside its other limits.** Turns and
  wall-clock each had a ceiling, and a run could sit comfortably within both
  while looping; the daily cap was read only *before* a ticket was picked up,
  so runs already in flight could pass it together with nothing to stop them.
  Each phase now carries a generous token ceiling, and the ledger is consulted
  on a timer while the run works. It counts tokens rather than dollars because
  tokens are in the stream exactly and a price table here would be invented and
  then drift — the money control remains the realm's daily cap.
- The stale-run sweeper uses each phase's own time limit. Per-phase budgets
  gave review 5400s while the sweeper still killed anything quiet for 2820s,
  so a long review was marked dead while it was still working — the same class
  of bug as the earlier 900s-vs-2700s mismatch, in the other direction.
- **A Ruby project's `bundle exec` no longer resolves against this app's
  bundle.** `BUNDLE_PATH`, `BUNDLE_DEPLOYMENT`, `RUBYOPT` and the rest are set
  in the image and inherited by every child process, so an agent running
  `bundle exec rspec` in your repo was pointed at barad-dûr's own production,
  deployment-mode gems.
- The pipeline's own `.pipe/` record is excluded from the diff preview. It is
  committed with the work, so it was the first thing the drawer's forty lines
  showed.
- **Pause now pauses, and the daily cap now caps.** Both stopped the tower
  picking up new work while letting every ticket already in flight run all its
  remaining phases — the opposite of what either control is for. A ticket that
  reaches its next phase while the tower is stopped is held there, says which
  of the two held it, and is picked up when the tower runs again.
- **Planning marks a ticket risky.** The `risky` autonomy mode asks you before
  an agent writes code on a dangerous change, and it reads a flag only a human
  checkbox ever set — so it did nothing for the tickets that most needed it.
  Planning has read the code by then, so it now says whether the change touches
  a schema, authentication, money, data deletion or a public API, and why. It
  can only escalate: a ticket you marked risky stays risky.
- **Every ticket was inheriting the previous ticket's commits.** The work branch
  was cut from wherever HEAD happened to sit, and the last ticket leaves the
  repo on its own `pipe/*` branch. Branches are now cut from the base branch.
- The base branch is asked of the repository rather than guessed as "main, else
  master" — the remote's own HEAD first, then the configured default, then the
  conventional names. A project whose trunk is `develop`, or one that renamed to
  `main` and left a stale `master` behind, was diffed and merged against the
  wrong branch.
- Work the agent changed but never committed is surfaced on the ticket and in
  the diff. It is invisible to a branch diff and absent from the pull request,
  so it silently did not ship.
- The diff preview says how many lines it left out instead of stopping at forty
  as though that were the whole change.
- A harness implementation run no longer requires an openspec change to exist.
  Without one the phase fell back to the built-in prompt, so a repo without
  openspec never used its own harness for the one phase that writes code.

## [1.1.0] — 2026-08-18

The first release driven by running the pipeline on real work. Most of it
comes from what that surfaced: every ticket failing for reasons the app
would not explain, and a money panel that was quietly wrong.

### Added

- **The reckoning** on the dashboard: cost per shipped ticket, first-pass rate
  with the cost of rework, and how much of the elapsed time was spent waiting on
  a person rather than on an agent.
- Spend broken down by pipeline stage, by model and by source, plus today's burn
  projected to midnight against the cap.
- The framework step lists every harness in the workspace — each repo, their
  immediate sub-projects and the workspace root — and lets you choose which one
  drives the phases instead of always taking the first one found. A deliberate
  choice may sit outside the selected repos, where auto-detection still may not;
  an invalid or since-removed path falls back to auto, and a path pointing
  outside the workspace is refused.
- Clarifying questions can be answered from the ticket drawer, not only the
  dashboard.

### Fixed

- Spend is a ledger rather than a running total. Three separate counters could
  drift apart, none of them reset, and the daily cap was really a lifetime one.
  Every charge is now a row, so "today" resets at midnight on its own and the
  per-agent, per-ticket and global figures cannot disagree.
- Money is kept to four decimal places. Rounding every charge to whole cents
  lost sub-cent runs entirely and over-counted mid-priced ones by about 15%.
- Charges are recorded with an insert rather than a read-modify-write, so runs
  in the web and ticker processes can no longer lose each other's spend.
- Runs that failed recorded $0 no matter what they had spent, because cost was
  only read on the success path. Failures are charged now, and a migration
  recovers what earlier ones cost from their own captured output.
- A failed run said what the agent happened to be saying when it stopped
  ("Now the design.md corrections:") rather than why it stopped. It now reports
  the real cause — turns exhausted, terminated, or denied commands — with what
  to change.
- The hourly spend bars cover a contiguous run of hours. They previously drew
  the last fourteen hours that happened to have rows, so idle hours vanished and
  unrelated hours appeared side by side.
- Feature-request and archive charges are attributed to their ticket and agent;
  previously they were counted only in the global total.
- A workspace with no harness is cached as such instead of being rescanned on
  every render.

### Changed

- Agent runs allow shell commands in the selected repositories. `acceptEdits`
  denied every Bash call, so the testing stage could never run a suite and
  implementation runs burned their turns retrying denied commands.
- Turn and time limits raised to 120 turns and 45 minutes. At 40 turns every
  real ticket died mid-task at turn 41, having spent its money for nothing.
- Restarting while over the cap now overrides the cap for the rest of the day
  instead of zeroing the spend counter; the ledger keeps its history.
- The live event feed has a maximum height and scrolls within it instead of
  pushing the rest of the dashboard down the page.
- The phase strip on a board card animates: the executing phase sweeps, a
  reached one glows, a failed one pulses.

## [1.0.0] — 2026-08-17

First public release. Everything below was built during initial development; the version
history starts here.

### The pipeline

- Ticket state machine covering draft, ready, investigation, planning, ready-to-implement,
  implementation, review, testing, deployment and done
- **Blocked** as a derived board column with four subtypes — clarification, dependency,
  gate and failure — where tickets return to their real column the moment the blocker clears
- Dependency enforcement between tickets: nothing starts before what it waits on is done
- Row-locked pickups and transitions, so the web process and the ticker can never claim
  the same ticket
- Autonomy levels (unleashed, wary, chained) with approval gates, switchable mid-run
- Daily spend cap that pauses the pipeline before it is exceeded
- Restart recovery: orphaned runs surface as failed and retryable, and stale runs past the
  CLI timeout are swept

### Agents

- Every phase executes a real headless agent session, reporting its narration, cost,
  branches, commits and diffs
- Structured output parsed from fenced JSON, covering clarifying questions, plans with
  dependencies and splits, and test results
- Automatic detection of a repository's own agent harness — its commands, skills and agent
  definitions are mapped onto pipeline phases, with per-phase overrides and a built-in
  fallback for anything unmatched
- A roster staffed from the harness where it matches and built-in defaults elsewhere;
  unmatched harness agents become delegation specialists
- Selectable orchestrator model
- Two authentication modes, subscription or API key, with each mode's credentials isolated
  from the other

### Working with your code

- Workspace folder chooser supporting a single repository or a folder of many, with
  monorepo sub-project targeting
- Per-repository selection: only the repositories you tick can be modified, and that
  selection is honoured by ticket targets, harness detection and every count shown
- All work happens on `pipe/*` branches; approved work merges locally with a merge commit
- Optional push and pull request creation, with acceptance criteria carried into the
  description
- Change archiving through the harness after a merge
- Specification indexing, with agents held to what is written there
- Test results captured from the testing phase and shown on the dashboard

### Interface

- Six screens: dashboard, board, feature request, specs, agents and activity
- Ticket drawer with summary, technical notes, acceptance criteria, per-phase logs with
  cost and exit code, the real diff, and merge, request-changes and push actions
- Editing and deleting parked tickets, plus a shipped history view
- Feature request flow: describe, investigate, clarify, plan, push to the board
- Resumable conversation threads per ticket and one for the workspace, rendered as markdown
- Live updates throughout without page reloads, and an attention badge on the browser tab
- Dark and light themes
- Five-step setup wizard

### Operations

- Docker Compose for development and a separate production profile
- Runs without Node, Redis or a separate job server: import maps for JavaScript, and the
  queue, cache and cable all backed by PostgreSQL
- Test suite of 84 runs covering the full agent path against a stub CLI, so tests never
  spend anything

[Unreleased]: https://github.com/bl0rch1d/barad_dur/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/bl0rch1d/barad_dur/releases/tag/v1.1.0
[1.0.0]: https://github.com/bl0rch1d/barad_dur/releases/tag/v1.0.0
