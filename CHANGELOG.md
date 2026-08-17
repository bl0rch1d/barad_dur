# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Spend is a ledger rather than a running total. Three separate counters could
  drift apart, none of them reset, and the daily cap was really a lifetime one.
  Every charge is now a row, so "today" resets at midnight on its own and the
  per-agent, per-ticket and global figures cannot disagree.
- Money is kept to four decimal places. Rounding every charge to whole cents
  lost sub-cent runs entirely and over-counted mid-priced ones by about 15%.
- Charges are recorded with an insert rather than a read-modify-write, so runs
  in the web and ticker processes can no longer lose each other's spend.
- The hourly spend bars cover a contiguous run of hours. They previously drew
  the last fourteen hours that happened to have rows, so idle hours vanished
  and unrelated hours appeared side by side.
- Feature-request and archive charges are attributed to their ticket and agent;
  previously they were counted only in the global total.

### Added

- **The reckoning** on the dashboard: cost per shipped ticket, first-pass rate
  with the cost of rework, and how much of the elapsed time was spent waiting on
  a person rather than on an agent.
- Spend broken down by pipeline stage, by model and by source, plus today's burn
  projected to midnight against the cap.

- Runs that failed recorded $0 no matter what they had spent, because cost was
  only read on the success path. Failures are charged now, and a migration
  recovers what earlier ones cost from their own captured output.
- A failed run said what the agent happened to be saying when it stopped
  ("Now the design.md corrections:") rather than why it stopped. It now
  reports the real cause — turns exhausted, terminated, or denied commands —
  with what to change.

### Changed

- Restarting while over the cap now overrides the cap for the rest of the day
  instead of zeroing the spend counter; the ledger keeps its history.
- Agent runs allow shell commands in the selected repositories. `acceptEdits`
  denied every Bash call, so the testing stage could never run a suite and
  implementation runs burned their turns retrying denied commands.
- Turn and time limits raised to 120 turns and 45 minutes. At 40 turns every
  real ticket died mid-task at turn 41, having spent its money for nothing.
- Clarifying questions can be answered from the ticket drawer, not only the
  dashboard.
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

[Unreleased]: https://github.com/bl0rch1d/barad_dur/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bl0rch1d/barad_dur/releases/tag/v1.0.0
