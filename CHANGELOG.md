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
