<!-- Ash nazg durbatulûk, ash nazg gimbatul, ash nazg thrakatulûk agh burzum-ishi krimpatul. -->
<!-- (One Pipeline to rule them all, One Pipeline to find them, One Pipeline to bring them all, and in the darkness `git bind` them.) -->

<div align="center">

<img src="docs/assets/logo/ember/barad-dur-seal-disc-256.svg" width="160" alt="The Seal of Barad-dûr">

# BARAD-DÛR

***the Eye is open · the watch holds***

**A mission-control tower for a legion of coding agents — they investigate, plan, implement,
review and ship real work in your repositories, while you sit on the dark throne and approve.**

[![Rails](https://img.shields.io/badge/Rails-8.1-8fd9ad?logo=rubyonrails&logoColor=white&labelColor=0a0705)](https://rubyonrails.org)
[![Ruby](https://img.shields.io/badge/Ruby-3.4-8fd9ad?logo=ruby&logoColor=white&labelColor=0a0705)](https://www.ruby-lang.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-8fd9ad?logo=postgresql&logoColor=white&labelColor=0a0705)](https://www.postgresql.org)
[![Docker](https://img.shields.io/badge/Docker-compose%20up-8fd9ad?logo=docker&logoColor=white&labelColor=0a0705)](https://docs.docker.com/compose/)
[![Agents](https://img.shields.io/badge/agents-Claude%20Code-ff5a1a?labelColor=0a0705)](https://claude.com/claude-code)
[![Trials](https://img.shields.io/badge/trials-65%20passed%20in%20the%20fires-5fa87e?labelColor=0a0705)](#-the-trials)

[The Tower](#-what-rises-here) • [The Palantír](#-gaze-into-the-palantír) • [Speak, Friend, and Enter](#-speak-friend-and-enter) • [The Legion](#%EF%B8%8F-the-legion) • [The Forging](#-how-the-work-is-forged) • [Words of Command](#-words-of-command) • [The Road Ahead](#%EF%B8%8F-the-road-goes-ever-on)

</div>

---

## 🗼 What rises here

Barad-dûr is a self-hosted web app that runs a **complete software development lifecycle on autopilot** —
with you as the Lidless Eye atop it. Describe a feature in plain speech, and the tower:

1. **Investigates** your actual repositories (read-only — Scouts do not touch, only see),
2. **Asks** the questions it will not guess at (clarifications become blocking *SUMMONS*),
3. **Plans** an ordered ticket campaign with dependencies and acceptance criteria,
4. **Implements** on `pipe/*` branches with real commits — never on your default branch,
5. **Reviews, tests**, and finally waits at the gates of your judgment:
   **Approve & merge**, or hurl the work back whence it came with feedback.

Every agent is a real headless [Claude Code](https://claude.com/claude-code) session. Every diff is a real diff.
Every dollar of **Tribute burned** is real spend, capped daily — the tower pauses itself before it beggars you.

> *"It needs but one Eye to command a legion."* — the Setup Wizard, step 5 of 6, probably

## 🔮 Gaze into the palantír

| The Watchtower at Night | The Shire Variant ☀️ |
|:---:|:---:|
| ![Dashboard — dark theme](docs/assets/screenshots/dashboard-dark.png) | ![Dashboard — light theme](docs/assets/screenshots/dashboard-light.png) |

*Left: ember and shadow, as the Dark Lord intended. Right: for those who yet walk in the daylight of the Westlands (your PM).*

**What you're seeing** — in the Common Tongue:

| In the Black Speech | In Westron (what it actually is) |
|---|---|
| **The Cold Watch** | Live event feed — every agent thought, tool call and phase change, streamed |
| **The Eye demands** | Your action center: clarifying questions, approval gates, failed runs to retry |
| **The Legion** | The agent roster — auto-mapped from your repo's own `.claude/agents` harness |
| **SUMMONS** | An approval gate. Nothing risky moves until you say so |
| **Tribute burned** | Real API spend, hourly bars, hard daily cap |
| **Unleashed / Wary / Chained** | Autonomy modes: full auto → gate risky things → gate everything |
| **Quench / Kindle** | Pause / start. The forge answers to you alone |

## 🚪 Speak, friend, and enter

The doors of Barad-dûr open considerably easier than the doors of Durin — no Elvish riddle required:

```bash
git clone git@github.com:bl0rch1d/barad_dur.git && cd barad_dur
docker compose up
```

Then walk into **http://localhost:3000**. You arrive in *demo mode*: a fully simulated trading-platform
workspace where agents pretend very convincingly. No keys, no cost, no consequences. Poke everything.

### Binding it to your own lands (live mode)

```bash
# mount a folder of repos (multi-repo) or a single repo (monorepo)
WORKSPACE_PATH=~/dev docker compose up
```

Auth is chosen in the wizard — **Claude subscription is the default** (your host's `~/.claude`
login is mounted in automatically; no per-token billing), or set `ANTHROPIC_API_KEY` for metered use.
The runner passes only the chosen credential to agents, so the two never cross streams.

Walk the Setup Wizard (six steps, one tower):

1. **Folder** — browse the mount, pick monorepo or multi-repo, check what the pipeline may own
2. **Auth** — subscription or key, plus the orchestrator model (Opus 5 rules them all by default)
3. **Framework** — your own agentic harness is auto-detected: commands in `.claude/commands`
   map onto phases (`/opsx:explore` → investigation, `/opsx:propose` → planning, `/opsx:apply` → implementation, `/review` → review)
4. **Parse** — your `openspec/` specs are indexed with a progress bar that does not lie
5. **Autonomy** — pick your leash: *Unleashed*, *Wary*, or *Chained*
6. **Go live** — the demo world is unmade before your eyes; your real one takes its place

> **One does not simply merge into master.** Work lands via `--no-ff` merge commits from `pipe/*`
> branches, only after review, only local, and only when you press the button. The tower never pushes.

## ⚔️ The Legion

If a repo in your workspace carries a `.claude/agents/` folder, its **own agents** take the phases
they match; built-ins fill the gaps. The rest muster as **delegation specialists** — spawned inside
runs via the Task tool, never assigned tickets of their own.

| Phase | Who answers the summons | Lineage |
|---|---|---|
| Investigation | `explorer` | your harness |
| Planning | `planner` | your harness |
| Implementation | `Builder` | built-in |
| Review | `reviewer` (+ a verifier wave) | your harness |
| Testing | `Tester` | built-in |
| Deployment | `Shipper` | built-in |

No harness? The default seven serve faithfully. They are not evil, merely… *ambitious*.

## 🔥 How the work is forged

```
      draft ──groom──▶ ready ──▶ investigation ──▶ planning ──▶ ready to implement
                                      │                │                │
                                  questions?       openspec         SUMMONS?
                                 (Eye demands)      change            (gate)
                                                                        │
                              done ◀── deployment ◀── testing ◀── review ◀── implementation
                               │                                    │            (pipe/* branch,
                            merged by                        Approve & merge      real commits)
                            your hand                       or Request changes
```

- **Feature requests** run your harness end-to-end: `/opsx:explore` investigates, surfaces
  clarifying questions, `/opsx:propose` writes the change artifacts and files dependency-ordered
  tickets — which land *ready to implement*, because re-planning planned work is for goblins.
- **Blocked** is a derived column with subtypes (clarification / dependency / gate / failed) —
  tickets return to their place the moment the blocker falls.
- **Dependencies are law**: nothing starts before what it awaits is done; the web and the ticker
  contend for tickets under row locks, so no two Nazgûl claim the same prey.
- **The palantír chat** (Activity) holds a real resumable agent session per ticket plus one for
  the whole realm — steer mid-flight; the session remembers, as palantíri do. Use responsibly.
- Restart-proof: orphaned runs surface as *failed, retryable*; seeds never trample a live realm;
  the favicon grows a burning badge when the Eye demands your presence in another tab.

## 📜 Words of Command

| Rune | Effect | Default |
|---|---|---|
| `WORKSPACE_PATH` | Host folder mounted as the realm | `./workspace` |
| `ANTHROPIC_API_KEY` | Metered auth (wizard: "API key") | — |
| `CLAUDE_CONFIG_PATH` | Subscription login mount | `~/.claude` |
| `PIPELINE_RUNNER` | `auto` · `demo` · `live` | `auto` |
| `CLAUDE_MODEL` | Override the orchestrator model | wizard choice (Opus 5) |
| `CLAUDE_FLAGS` | Extra CLI flags for agent runs | `--permission-mode acceptEdits` |
| `CLAUDE_MAX_TURNS` / `CLAUDE_TIMEOUT` | Patience of the tower | `40` / `900s` |
| `PIPELINE_TICK_INTERVAL` | Heartbeat of the forge | `3.2s` |

## 🔬 The Trials

```bash
docker compose exec web bin/rails test
# 65 runs, 395 assertions, 0 failures — passed in the fires of Mount Doom (a stub CLI;
# no tokens were sacrificed, the whole live path is hermetically testable)
```

## 🗺️ The Road Goes Ever On

- [ ] Test-result capture — the testing phase's pass/fail counts, told truly on the dashboard
- [ ] Push & PR flow — optional `gh` tribute to the far lands of GitHub, plus `/opsx:archive` after merge
- [ ] Production deploy scrolls — for towers that must stand outside one's own machine
- [x] Everything else you can see. It took nine days. Make of that number what you will.

## 🤝 Fellowship

Issues and pull requests are welcome — even from Elves.
Second breakfast is not provided but is respected.

## 🪶 Acknowledgments & License

Forged with [Claude Code](https://claude.com/claude-code) from a [Claude Design](https://claude.ai/design) prototype.
Themed in tribute to Professor Tolkien; not affiliated with Middle-earth Enterprises.
**Sauron provided no code review** — all defects are the maintainer's own.

License: none declared yet. *It's ours, precious.* (Open an issue if you need one.)

<div align="center">
<sub>No hobbits were harmed in the making of this pipeline. One (1) Balrog was mildly inconvenienced.</sub><br>
<sub><i>"Not all those who wander are lost — some are just watching the Cold Watch scroll."</i></sub>
</div>
