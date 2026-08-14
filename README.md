# barad_dur — agentic SDLC pipeline

A Rails web app implementing the **"SDLC Pipeline"** Claude Design prototype: a
mission-control dashboard for a fleet of coding agents that carry tickets
through Investigation → Planning → Implementation → Review → Testing →
Deployment on a simulated trading-platform workspace ("algo").

The pipeline mechanics are real — a state machine with phase runs, autonomy
gates, human-blocking questions, spend accounting and live Turbo Stream
updates — and it runs in one of two modes per ticket:

- **Live mode**: phases execute as real headless **Claude Code** runs inside
  your mounted workspace repositories (see *Live mode* below).
- **Demo mode**: a simulated driver with canned narrative, used automatically
  whenever the CLI, auth, or the ticket's repo aren't available.

## Stack

- **Rails 8.1** (Ruby 3.4), PostgreSQL 17
- **Hotwire**: Turbo 8 morphing page refreshes + Stimulus, importmap (no Node)
- **Solid Cable** for cross-process Action Cable (also in development)
- Plain CSS design tokens ported from the design prototype (dark/light themes)
- Docker Compose: `db` (postgres) + `web` (puma) + `ticker` (pipeline loop)

## Run it

```sh
docker compose up
```

Then open <http://localhost:3000>. First boot builds the image, creates and
seeds the database. The `ticker` service advances the pipeline every ~3s and
every open browser tab updates live.

## Screens

| Screen | What it does |
|---|---|
| Dashboard | Live event feed, now-running card, gate banner, "Needs you" questions, agents, CI, commits, changelog, cycle-time by phase |
| Board | 8-column kanban of tickets; click a card for the ticket drawer |
| Feature request | RFC flow: describe → investigate (trace) → clarify (questions) → plan → push tickets to the board |
| Specs | openspec capability browser (requirements + Gherkin scenarios) |
| Agents | The 7 agent roles, what they're doing, tools, spend |
| Activity | Ticket-scoped chat with the Architect (replies async) + event stream |

Overlays: ticket drawer (`?ticket=ALG-207`) and the 5-step setup wizard
(`?wizard=1`), both URL-driven so they survive live refreshes.

Titlebar controls: autonomy (**Full auto / Gate risky / Gate all**),
dark/light theme, and Pause/Start/Stop. With gating enabled, transitions wait
for your approval in the dashboard gate banner. Answering a "Needs you"
question unblocks the ticket. When the daily spend cap ($80) is reached the
pipeline pauses itself; pressing Start begins a fresh budget window.

## Live mode — run the pipeline on your own repos

1. Put (or clone) git repositories under `./workspace/` — or point
   `WORKSPACE_PATH` at an existing folder:

   ```sh
   WORKSPACE_PATH=~/dev docker compose up
   ```

   Both layouts work — a **multi-repo** folder (contains git repositories) or
   a **monorepo** (the folder *is* a git repository). The wizard's Folder step
   is a real chooser: browse folders inside the mount (rows are annotated
   "git repository — select as monorepo" / "N repos inside"), click to
   descend, `..` to go up; the selected folder becomes the active workspace
   (persisted, never escaping the mount). For monorepos, common sub-projects
   (package.json, Gemfile, go.mod, …) are detected and offered as ticket
   targets like `mono/apps/web` — the agent is then scoped to that
   subdirectory while git operations stay at the repo root.

2. Provide auth for the agent runner — two modes, chosen in the wizard's
   Auth step (**Claude subscription is the default**):

   - **Claude subscription** (default): your host's `~/.claude` login is
     mounted into the containers automatically (`CLAUDE_CONFIG_PATH` overrides
     the location), so if you're logged into Claude Code on this machine it
     just works. Alternatively set `CLAUDE_CODE_OAUTH_TOKEN` (from
     `claude setup-token`, Pro/Max). No per-token billing.
   - **API key**: metered per-token billing via the environment:

     ```sh
     ANTHROPIC_API_KEY=sk-ant-... docker compose up
     ```

   The runner passes only the chosen mode's credential to the spawned CLI, so
   subscription runs never silently bill an API key and vice versa.

3. Open the setup wizard: step 1 shows the actually-mounted repos (pick what
   the pipeline owns), step 2 shows key/runner status, step 4 parses real
   `openspec/specs/*/spec.md` files into the Specs screen (there is also a
   "⟳ rescan" button on the Specs screen).

4. File a ticket from the Board's inline form against a workspace repo. When
   an agent picks it up, each phase spawns `claude -p` in that repo:
   investigation (read-only) → plan written to `openspec/changes/` →
   implementation on a `pipe/<ticket>` branch with real commits → review →
   tests → changelog entry. The event feed streams the agent's actual
   messages and tool calls; costs are the real API costs; the drawer shows
   the real diff, run log, and a **retry** button for failed runs.

Autonomy gates apply to live runs exactly as to demo ones — "Gate risky" /
"Gate all" hold the next phase until you approve it in the dashboard.

Tuning via environment: `PIPELINE_RUNNER` (`auto`|`demo`|`live`),
`CLAUDE_FLAGS` (default `--permission-mode acceptEdits`), `CLAUDE_MAX_TURNS`
(40), `CLAUDE_TIMEOUT` (900s), `CLAUDE_BIN` (alternate binary — the test
suite points this at `test/fixtures/files/fake_claude` to run the whole live
path offline).

**Safety notes**: agents edit files and create branches/commits in your
mounted repos (never push). `acceptEdits` auto-approves file edits only; use
a throwaway clone the first time, and raise permissions consciously (e.g.
`CLAUDE_FLAGS="--dangerously-skip-permissions"`) only if you accept the risk.
Ticket codes/titles you enter are passed to the agent as prompt text.

## How it works

- `PipelineEngine.tick!` (app/services) advances demo tickets by phase
  thresholds, consults the autonomy setting to create `Gate`s, emits `Event`s,
  accrues spend, frees agents, and pulls/grooms backlog so the board never
  runs dry. Every tick broadcasts a Turbo morph refresh to all clients.
- Live tickets are event-driven instead: `AgentRunner` decides per ticket,
  `RunPhaseJob`/`ClaudeCodeRunner` spawn the CLI (stream-json), and on success
  hand the ticket back to `PipelineEngine.phase_finished!` for the (possibly
  gated) transition. `PhasePrompts` defines what each phase asks the agent to
  do; `Workspace`/`SpecSync` handle repo scanning and openspec parsing.
- `DemoScript` / `RfcScript` supply the canned narrative for demo tickets and
  the (still simulated) RFC investigation flow.
- `lib/tasks/pipeline.rake` is the tick loop run by the `ticker` service
  (`PIPELINE_TICK_INTERVAL` to tune, `DISABLE_RELOADING=1` because a
  non-request process shouldn't pay dev-mode reload checks).
- Cycle-time stats are computed from real `PhaseRun` durations.

## Tests

```sh
docker compose exec web bin/rails test
```

## Notes

- `db/seeds.rb` recreates the prototype's demo workspace; wipe with
  `docker compose down -v` to reseed on next boot.
- The production `Dockerfile` generated by Rails is kept for deploys; run the
  ticker as a separate process (`bin/rails pipeline:ticker`) there too.
- The Ticket enum's first state is `:backlog` (displayed "Not ready") because
  Rails auto-generates a `not_ready` negation scope for the `:ready` value.
