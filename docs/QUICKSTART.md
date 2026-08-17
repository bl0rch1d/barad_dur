# Quick Start

Getting Barad-dûr running on your own machine, from nothing to a working pipeline.
Budget about **ten minutes**, most of it waiting for a container to build.

New here? [How It Works](HOW-IT-WORKS.md) explains what this actually does, in plain
English, before you install anything.

---

## What you need first

| Requirement | Why | Check it |
|---|---|---|
| **Docker** with Compose v2 | Everything runs in containers — no Ruby, Postgres or Node on your machine | `docker compose version` |
| **Git** | To clone this repo, and because the pipeline works with git branches | `git --version` |
| **An AI coding account** | The agents are real sessions; see below | — |
| **Some code to work on** | One repository, or a folder containing several | — |
| ~3 GB free disk | Container images and the database | — |

Ports **3000** (the app) and **5432** (Postgres, internal only) should be free.

### Choosing how the agents authenticate

Pick one. You'll confirm the choice in the setup wizard.

**Option A — your existing subscription** *(default, no per-token billing)*

Install [Claude Code](https://claude.com/claude-code) on your machine and log in once:

```bash
npm install -g @anthropic-ai/claude-code
claude          # follow the login prompt, then exit
```

That login is stored at `~/.claude/.credentials.json`. Barad-dûr mounts that folder into
the container read-only, so the agents inherit your session. Nothing else to configure.

**Option B — an API key** *(pay per use)*

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Set it in the shell you start the app from, and choose "API key" in the wizard.

> The container has its own copy of the agent CLI, so you don't strictly need it installed
> locally for Option B — but you do for Option A, since that's where the login lives.

---

## Install and run

### 1. Get the code

```bash
git clone git@github.com:bl0rch1d/barad_dur.git
cd barad_dur
```

### 2. Point it at your projects

The one setting that matters is **`WORKSPACE_PATH`** — the folder the pipeline is allowed
to see. Both layouts work and are detected automatically:

```bash
# A folder containing several repositories
WORKSPACE_PATH=~/dev docker compose up

# Or a single repository (a monorepo, or just one project)
WORKSPACE_PATH=~/dev/my-project docker compose up
```

Point it at a **parent folder** if you want the pipeline to work across several
repositories at once. You choose which of them it may modify in the wizard; the rest stay
readable but untouchable.

> **Tip:** try it on a repository with a git history and some tests. The agents lean on
> both, and you'll see much better results than on an empty project.

### 3. Wait for the first build

The first `docker compose up` builds the image and prepares the database — expect a few
minutes. You're ready when you see:

```
web-1  | * Listening on http://0.0.0.0:3000
```

### 4. Open it

Go to **http://localhost:3000**.

Every page will say the realm is unbound — that's just "setup isn't done yet". Click
**Bind the realm — Setup wizard**.

### 5. Walk the wizard — five steps, once

| Step | What you do |
|---|---|
| **1. Folder** | Browse to your project or folder of projects, then tick the repositories the pipeline may change |
| **2. Auth** | Confirm subscription or API key — it tells you whether it can see your credentials — and pick the model that orchestrates |
| **3. Framework** | If your project has its own agent commands, they're detected here and mapped onto the pipeline stages. Otherwise the built-in prompts are used. Nothing to do either way. |
| **4. Parse** | Indexes any written specifications it finds. Wait for the indexing bar to finish — Continue unlocks when it's done. |
| **5. Autonomy** | Choose **Chained** for your first run (it stops for approval at every stage), then press start |

That's it. The board is live.

### 6. Your first ticket

On the **Board**, type one line into the composer — something small and low-risk:

> *Add a --version flag to the CLI*

Press **File draft**, then **Groom** on the card that appears. It will investigate, plan,
and stop where your autonomy setting says to stop. Watch the **Dashboard** for anything
waiting on you.

---

## Everyday commands

```bash
docker compose up -d          # start in the background
docker compose logs -f web    # watch what it's doing
docker compose down           # stop (your data is kept)
docker compose down -v        # stop and erase the database — full reset
docker compose exec web bin/rails test    # run the test suite
```

To pause the agents without stopping the app, press **Quench** in the title bar.

---

## Settings you might want

All optional — set them in front of `docker compose up`, or copy `.env.example` to `.env`
and edit it there (Compose reads `.env` automatically, and it is gitignored).

| Setting | What it does | Default |
|---|---|---|
| `WORKSPACE_PATH` | The folder of code the pipeline can see | `./workspace` |
| `ANTHROPIC_API_KEY` | API key, if not using a subscription | — |
| `CLAUDE_CONFIG_PATH` | Where your subscription login lives | `~/.claude` |
| `PIPELINE_RUNNER` | Set to `off` as a kill switch — nothing will run | `auto` |
| `DISABLE_RELOADING` | Set to `1` for noticeably faster pages when you aren't editing the app's own code | `0` |
| `CLAUDE_MODEL` | Override the orchestrating model | wizard choice |
| `CLAUDE_MAX_TURNS` / `CLAUDE_TIMEOUT` | How long an agent may work on one stage | `40` / `900s` |
| `GH_TOKEN` | Needed only for the optional "Push & PR" button | — |

A daily **spend cap** (default `$80`) is set in the app itself, not here. Reaching it
pauses the pipeline.

---

## When something goes wrong

**"Port 3000 is already in use"**
Something else is on that port. Either stop it, or edit the `ports:` line in
`docker-compose.yml` to `"3001:3000"` and use http://localhost:3001.

**The wizard says it can't see my credentials**
For subscription auth, check the file exists: `ls ~/.claude/.credentials.json`. If it
doesn't, run `claude` on your machine and log in. If your config lives elsewhere, set
`CLAUDE_CONFIG_PATH` to that folder. For API keys, confirm `ANTHROPIC_API_KEY` is set in
the same shell you started Docker from — `docker compose config | grep ANTHROPIC` shows
what actually reached the container.

**No repositories found in step 1**
`WORKSPACE_PATH` is pointing at the wrong place, or the folders there aren't git
repositories (each needs its own `.git`). Confirm with
`docker compose exec web ls /workspace`.

**Everything feels slow**
Almost always a filesystem issue: code on a Windows drive accessed from WSL, or a network
mount, is slow to scan. Move the repositories onto the Linux filesystem if you can, and
set `DISABLE_RELOADING=1`.

**A ticket is stuck as failed**
Open it and read the stage log — the agent's own output says what happened. Press
**Retry** on that stage. Failures after a restart are expected: jobs die with their
process and are marked retryable on the next boot.

**I want to start completely fresh**
`docker compose down -v && docker compose up` erases the database and returns you to the
setup wizard. Your code is never touched by this.

---

## Where to go next

- **[How It Works](HOW-IT-WORKS.md)** — what the system does and why, with diagrams
- **[README](../README.md)** — feature tour, architecture diagrams, configuration
- **Deploying it somewhere other than your laptop** — see the production section of the
  README

---

## Is any of this risky?

Worth knowing before you leave it running:

- Agents work on **separate branches** (`pipe/…`) and never on your main branch
- Nothing merges without you clicking **Approve & merge**
- Nothing is pushed anywhere unless you click **Push & PR**
- Repositories you didn't tick in step 1 are readable but never modified
- The spend cap stops the pipeline before your bill grows

The honest caveat: agents run with permission to edit files in the repositories you
selected. Committed work is recoverable through git; uncommitted work in those
repositories is not. **Commit or stash anything you care about before your first run.**
