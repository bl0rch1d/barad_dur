<!-- Implemented. Kept for the reasoning, not as a plan. -->

# Proposal: a default agentic harness

**Status: built and shipped** — see the CHANGELOG entries under Unreleased.
This document is kept for its reasoning and its evidence, not as a plan.

Two deliberate departures from what is written below:

- **All six phases map to Sammath, not three.** §10 recommends mapping only
  investigation, planning and review by default and leaving the rest on the
  improved built-ins until a benchmark says otherwise. The request was to
  replace the default harness outright, so all six are mapped — with the
  per-phase override in the wizard as the way back, and each skill written to
  degrade rather than fail when an earlier phase ran on a built-in prompt and
  left it no contract.
- **The benchmark of §10 stage 1 was dropped, deliberately.** Stages 0 and 2
  shipped without it, on the grounds that every item in them was an
  independently verified live defect that did not need a benchmark to justify;
  the maintainer then decided to skip it outright rather than build it later.
  So the consequence stands and is worth stating plainly: **nothing here has
  been measured against the built-ins.** The case for the harness rests on the
  specific defects it closes, each of which was reproduced before it was
  fixed — not on the comparison this document argues for, which was never run.
  §10's gate — *"if stage 2 alone closes most of the gap, stages 3 and 4 need a
  much stronger case"* — was therefore never evaluated either way.

## Provenance

Researched by a 16-agent workflow: deep reads of
[`agentic_development_workflow`](https://github.com/) and `quant_development`'s `/review`
skill, of this app's own phase contracts, plus published guidance and literature on agent
decomposition and verification. Three independent designs were produced from different
angles (fidelity to the sources, minimalism, evidence-led), each adversarially critiqued,
then synthesised into the recommendation below.

## What was verified by hand

The proposal asserts several live defects in this codebase. These were checked directly
against the source rather than taken on trust:

| Claim | Verified |
|---|---|
| `Question#chosen` is written once and read nowhere — answered clarifications never reach any prompt | ✅ `app/models/question.rb:7` is the only write; no reads |
| `acceptance_criteria` never reach implementation, review or testing | ✅ referenced only in `PLANNING_CONTRACT`, which asks the planner to *produce* them |
| A harness-mapped phase runs with `chdir` set to the harness repo and is never told the target repo's path | ✅ `phase_prompts.rb:70` vs the prompt naming `ticket.repo` at `:118` |
| `prepare_branch` runs only for implementation and uses `checkout -B` | ✅ `claude_code_runner.rb:140-143` |
| The stale-run sweeper used a 900s fallback while the agent timeout is 2700s | ✅ — **fixed separately in `103c988`**, it was a regression |

Two corrections the research made to earlier analysis, both confirmed:

- `references/unit_dispatch.md` contains no literal string "openspec" but references its
  *artifacts* (`proposal.md`, delta specs, `design.md`, `SHALL`) in four prompt templates,
  so it is not portable as-is.
- Two passages in the review skill depend on the authoring ecosystem without mentioning
  openspec at all (the sibling-repo scan; the `knowledge/` rulebook), and break anywhere
  else regardless.

## Reading note

Section 7 lists what this app must change; sections 2 and 10 are the ones to read first if
short of time. Stage 0 and stage 2 of the plan are **harness-independent** — they fix live
defects and improve the existing built-in prompts whether or not the harness is adopted.

The proposed harness ships a `.claude/settings.json` with `PreToolUse` hooks restricting
destructive git commands. Note the proposal's own caveat: those hooks are advisory while
agents run under `bypassPermissions`.

---

# Sammath — barad_dûr's default harness

*A synthesis of Grond, Forge-A and Forge-B, after adversarial review. Every claim about barad_dûr below was verified against the source at `/mnt/c/Users/temaf/Desktop/self/barad_dur` on this branch; file and line references are real.*

---

## 1. The recommendation

**Sammath is a six-skill Claude Code harness shipped inside barad_dûr's image, plus a new Ruby service — `PhaseBrief` — that computes, writes and validates the handoff between every pair of phases.** It is organised around one idea: **the phase boundary belongs to Ruby, not to the next LLM.** Every phase is handed a machine-written brief (`<repo>/.pipe/<CODE>.brief.json`) that barad_dûr computed — absolute repo path, resolved base SHA, the *actual runnable* toolchain, untruncated acceptance criteria, answered clarification questions, the repo's own CLAUDE.md text, and an explicit list of which upstream sections are missing — and every phase must return a fenced JSON contract that barad_dûr parses, validates, and acts on. The skills supply judgment: what to investigate, how to cut a diff into review units, how to refute a finding, how to classify severity. They never supply state, never discover the toolchain, never parse `$ARGUMENTS`, and never assert a fact that Ruby could check. Where the three source designs left an invariant as an instruction to the next model ("if `## Findings` is absent, do a compressed version and say so"), Sammath computes the condition in Ruby, stamps it into the brief as `"degraded": ["findings"]`, and — for planning and implementation — refuses to start.

That single inversion is what the three adversarial critiques converged on independently. Critique 2 put it exactly: *"the design moves state into files and contracts but leaves every cross-phase invariant as an instruction addressed to the next LLM, while the mechanisms that could actually enforce them — `PhaseBrief`, a record parser, the JSON contracts, the PR draft gate — sit in Ruby doing nothing."* It is also what Anthropic's prompt-chaining guidance prescribes — *"programmatic checks (see 'gate' in the diagram below) on any intermediate steps"* — and it is the direct countermeasure to the dominant empirical failure mode: MAST measures **41.8% of multi-agent failures as specification issues**, with **~79% occurring before verification is reached**.

---

## 2. Why replace the built-ins

The built-in prompts in `app/services/phase_prompts.rb#body_for` are three to fifteen lines each and are, individually, not bad. The testing prompt in particular is better than either source's — it enumerates lint → unit → regression → e2e, says where to find commands (`package.json`, Rakefile, Makefile, tox.ini, CI workflows, CONTRIBUTING) rather than guessing, and carries the anti-cheat clause *"Never weaken, skip or delete a test to make it pass."* Sammath keeps that text nearly verbatim.

What they fail to do is concrete and verifiable:

**The pipeline drops its own specification on the floor.** `apply_plan_output` writes `acceptance_criteria` onto the ticket (`claude_code_runner.rb:325`), and `harness_prompt` passes only `code`, `title`, `description` and `feedback`. **The acceptance criteria the planner produced never reach implementation, review or testing.** Every phase after planning re-derives what the change is supposed to do from the code. This is Laban et al.'s sharded-underspecification regime (ICLR 2026 Oral: ~39% degradation across six generation tasks, *"once LLMs take a wrong turn they get lost and don't recover"*) reproduced deliberately by the harness.

**Answered questions are write-only.** `Question#answer!` sets `chosen` and `PipelineEngine.answer_question!` resumes the ticket. `grep -rn "chosen" app/ lib/` returns exactly one write and no reads. The pipeline asks the user a product question, parks the ticket, the user answers, the pipeline resumes — **and no prompt anywhere ever learns the answer.** This is a live bug today, independent of any harness.

**A harness-mapped phase cannot find the code.** `PhasePrompts.execution` sets `chdir: info.path` for harness runs; the prompt names `ticket.repo` (`"core"`, `"mono/apps/web"`) and never its path. Every bare `git` command a harness phase issues runs against the *harness* repo. Built-in phases don't hit this because they run with `chdir: repo_path` — which is also why they see the target repo's `CLAUDE.md` and harness phases never do.

**Nothing distinguishes "green" from "there was nothing to run."** `capture_test_results` returns early unless `passed`/`failed` are present (`:252`); `Ticket#last_test_run` accepts `tests_passed == 0` as present; `tests_failed?` is then false; `PushPrJob` opens a **non-draft, no-prefix pull request** on a repo where no suite exists. That is the worst possible failure direction and it is silent.

**Review has no output and no consequence.** `contract_for` returns `""` for review; `handle_structured_output` has no review branch. The built-in review prompt says *"Fix any real problems you find with additional commits"* — the reviewer fixing its own findings, which is precisely the conflict of interest source B's real reports carry a `⚠ Conflict-of-interest disclosure` for. `ticket.feedback` is written in exactly one place: a human clicking **Request changes**. A review that confirms a Critical bug writes prose to a log and the ticket advances.

**The diff base is wrong.** `capture_diff` uses the literal `main`/`master` ref, not the merge base, and excludes untracked files. On a branch that has fallen behind, barad_dûr's drawer diff and any reviewer's diff disagree about what changed.

**`prepare_branch` runs only for implementation, and uses `checkout -B`.** So investigation and planning execute on whatever branch the shared checkout happens to be on. With `MAX_IN_FLIGHT = 5` and one checkout per repo, ticket B's `checkout -B pipe/b` forks from ticket A's in-progress branch. And after a `BranchMerger` conflict (`merge --abort` leaves HEAD on base), a retry from the drawer runs `checkout -B` with HEAD on base and **silently discards every implementation commit**.

**A failed run discards everything, including work that succeeded.** `ClaudeCodeRunner#execute` skips `capture_outputs` and `handle_structured_output` entirely when `result.ok == false`. `HeadlessAgent` returns `ok: false` on both max-turns and timeout. A review that dispatched five of six agents and hit turn 118 produces no JSON, no report pointer, no questions — and the cost was already charged (`accrue_cost` runs first).

Sammath fixes all eight. Six of the fixes are Ruby and would be worth doing even if the harness were rejected.

---

## 3. The file tree

Two trees. The harness is **read-only and outside any git repository**, so no phase can drift it and a stray `git add -A` with a missing `-C` fails loudly rather than committing into barad_dûr's own source (critique 1, D2 — verified: barad_dûr has no root `CLAUDE.md` and no `.claude/`, so there is no guardrail file above a harness placed at `Rails.root`).

```
barad_dur/harness/                         # source of truth in the repo
  # Dockerfile: COPY harness/ /opt/barad-dur/harness/
  # Resolved at runtime as ENV["HARNESS_DIR"] || "/opt/barad-dur/harness",
  # falling back to Rails.root.join("harness") in dev with a warning Event.

  CLAUDE.md                    ~70 lines. Auto-loads because cwd is here for every phase
                               and every subagent. Holds the four house rules (§5), the
                               brief/record/contract schemas by reference, and the
                               forbidden-actions list. Zero Read calls, zero path fragility.
  VERSION                      Stamped; surfaced in the wizard and in every record header.
  .claude/
    settings.json              PreToolUse hook denying `git stash|checkout|reset|restore|
                               commit|apply` and `rm`/`>` redirects for the review agents.
                               Advisory under bypassPermissions — see §9.
    skills/
      explore/SKILL.md         ~90 lines → investigation
        references/intent.md   Step-0 intent discipline (source B, near-verbatim)
        references/questions.md  Question selector (source A's matrix, compressed)
      propose/SKILL.md         ~90 lines → planning
        references/contract.md   How to write criteria a test can assert; bugfix 3-task shape
      apply/SKILL.md           ~70 lines → implementation
      review/SKILL.md          ~180 lines → review (the largest, and correctly so)
        references/dispatch.md   Unit grouping, caps, the four prompt templates
        references/severity.md   Conditional anchors + the anti-rationalisation check
        references/refutation.md The six refutation routes + STANDS-must-correct
      test/SKILL.md            ~80 lines → testing
      ship/SKILL.md            ~70 lines → deployment
    agents/
      scout.md                 investigation fan-out (≤3); Read/Grep/Glob only
      review-unit.md           per-unit depth; model: sonnet; Read/Grep/Glob/Bash
      review-verifier.md       adversarial; model: sonnet; REFUTED by default
      fixer.md                 the review phase's single fix agent; Read/Edit/Write/Bash
```

Nineteen files. No `agents/` entry for planning, implementation, testing or deployment: barad_dûr's roster already names six agents and each phase is already an isolated process; a `planner.md` would rename "Architect" to "planner" in the UI and buy nothing. `scout` and the three review agents exist because they are *spawned*, not because they are named.

Per-ticket state, inside the target repo, on the `pipe/<code>` branch (which now exists from the first phase — see §7, B4):

```
<repo>/.pipe/.gitignore              "*.brief.json\n*.out.json"  — written once by Ruby
<repo>/.pipe/<CODE>.brief.json       Ruby-written, authoritative, never edited by an agent
<repo>/.pipe/<CODE>/contract.json    Frozen by planning: untruncated criteria, impact list,
                                     base sha, git hash-object digests of every existing test
<repo>/.pipe/<CODE>/record.md        Agent-owned. Seven headings, one owner each.
<repo>/.pipe/<CODE>/<phase>.out.json Each phase's contract JSON, written to disk as well as
                                     to the final message — survives a max-turns death
<repo>/.pipe/<CODE>/units/NN-*.md    Review subagent returns, written as they land
<repo>/.pipe/<CODE>/review-r<N>.md   Never overwritten; carries the refuted list forward
<repo>/.pipe/<CODE>/refuted.json     Cross-round verifier memory
```

The record has exactly seven headings, in order, one writer each — `## Intent` and `## Findings` (explore), `## Plan` (propose), `## Changes` (apply), `## Review` (review), `## Verification` (test), `## Ship` (ship). No metadata table, no Progress table, no session counter: `PhaseRun` rows already are the progress ledger, and duplicating live state is the drift bug source A's own CRITICAL block exists to paper over.

---

## 4. Per-phase specification

Common to all six. barad_dûr emits, as the entire prompt:

```
/explore ALG-42: Fix retry on biometric enrolment

BARAD-DUR-BRIEF=/workspace/core/.pipe/ALG-42.brief.json
BARAD-DUR-PHASE=investigation
BARAD-DUR-REPO=/workspace/core

Pipeline context: you are running non-interactively as the Scout agent for
ticket ALG-42 targeting repository core (scope: apps/web subdirectory).
Never ask the user questions interactively — AskUserQuestion does not exist
in this mode. Make reasonable choices and record them.
Project agents available for delegation via the Agent tool: scout.
<phase contract appended by PhasePrompts.contract_for>
```

**No skill parses `$ARGUMENTS`.** Two independent live probes against CLI v2.1.235 confirmed `$ARGUMENTS` expands to *everything after the invocation to the end of the prompt* — the context block, the feedback block and the fenced JSON contract included. Every source design's identity logic (source A's *"Read the argument file provided by the user"*, source B's input-shape detection table running `ls openspec/changes/<arg>/proposal.md` on a 20-line blob) breaks on contact. Step 1 of every SKILL.md is therefore, verbatim:

> **Step 1 — read your brief.** Your prompt contains a line `BARAD-DUR-BRIEF=<absolute path>`. Read that file. It is JSON, it was written by barad-dûr, and it is authoritative: where it disagrees with anything in your prompt or in the record, the brief wins. Do **not** parse `$ARGUMENTS` — in this harness it expands to the whole remaining prompt and is never a usable path. If the brief line is missing or the file will not parse, write nothing, change nothing, and end your final message with exactly `{"_c":"<phase>.v1","blocked":"brief unreadable"}` in a fenced json block.

Execution flags: `chdir` is the harness dir; `extra_args` are `--add-dir <workspace root> --add-dir <repo_path> --disallowed-tools AskUserQuestion`. Budgets per phase are returned from `PhasePrompts.execution` and passed to `HeadlessAgent.call` (which already accepts `max_turns:`/`timeout:` and is never given them today).

---

### 4.1 Investigation — `/explore`

**Invocation.** `/explore ALG-42: Fix retry on biometric enrolment` + the header block + `QUESTIONS_CONTRACT` + `board_context`. Budget: 60 turns / 1800s / $1.50.

**Responsibility.** Ground the ticket in repository evidence and write the one artifact every later phase quotes verbatim.

1. Read the brief. Read `repo_conventions[]` from it — that is the target repo's own `CLAUDE.md`/`AGENTS.md`/`CONTRIBUTING`, inlined by Ruby, because the harness cwd means the target repo's CLAUDE.md **never auto-loads** (confirmed by probe: `CLAUDE.md` loads from cwd only).
2. Classify the task. Bugfix indicators are source A's literal list, kept verbatim: `"bug", "error", "broken", "fix", "crash", "exception", "regression"`, stack traces, `"500"`, `"nil"`, `"undefined"`. On a bugfix, grep the repo for the literal error strings and stack frames from the ticket text and give a root-cause hypothesis with `file:line` evidence.
3. Locate the code. Grep the title and description terms; **read whole files, not match lines**; name affected files, call sites, the nearest existing implementation of the same shape, and the test files that already cover them.
4. Fan out only when it pays: **at most 3 `scout` subagents in a single message**, each scoped to one subsystem and one focus question, using source A's `/research` five-part report schema (components / data flows / entrypoints / config / conventions & concerns, every claim carrying `file:line`). One subsystem → inline, no subagent. The cap is Anthropic's own warning about *"spawning 50 subagents for simple queries."*
5. **One bounded gap pass** (source A `/research` Phase 2→3, kept because it runs once by construction and therefore cannot spin under a spend cap): re-read your collected findings against the ticket, list what is unsupported or untraced, fire at most two targeted follow-ups, stop.
6. Write `## Intent` — 3–6 lines stating what the change is *for*, in the direction the ticket states it, quoting any enumerated set or threshold **verbatim**. Source B's Step 0 rules ship as standing law: *"Never derive intent from a commit subject. Subjects compress, and the compression drops the distinction that matters."* And: never reconstruct intent from code — *"a reviewer who infers intent from the diff is grading the change against itself."* If the ticket says nothing about intent, say so plainly rather than inventing it.
7. Questions. Ask only when the answer would change an acceptance criterion or a file that will be edited **and** no defensible default exists. Source A's applicability matrix survives as the *selector*, not the script: PII, auth, authz, money, destructive migrations and public API shape make a category a mandatory candidate; everything else becomes a recorded assumption in `## Findings`, each with what would falsify it.
8. Modify no tracked file. Only `.pipe/`.

**Inputs it must be given as a fresh process.** `repo_path` (absolute), `scope_path`, `base_branch`, `base_sha`, `description`, `answered_questions[]`, `repo_conventions[]`, `toolchain` (for §4.2's benefit, not used here), `record_path`, `out_path`. Nothing from a prior conversation.

**Artifacts.** `record.md` with `## Intent` and `## Findings` (≤40 lines, capped by *content type* not by lines — the file:line list, the grep patterns that actually worked, the nearest existing implementation's path, the covering test files; those are the things expensive to re-derive and cheap to write).

**Returns.**
```json
{"_c":"investigation.v1",
 "questions":[{"q":"the decision","why":"why it matters","opts":["A","B"]}]}
```
0–2 questions, 2–3 options each, or the `questions` key omitted. Also written to `<repo>/.pipe/ALG-42/investigation.out.json`.

**Subagents.** `scout` ×≤3, plus ≤2 follow-ups. No adversarial agent — there is nothing to refute yet.

---

### 4.2 Planning — `/propose`

**Invocation.** `/propose ALG-42: …` + header + `PLANNING_CONTRACT` + `board_context`. Budget: 60 / 1800 / $2.00.

**Responsibility.** Turn intent into a frozen, machine-checkable contract. This phase exists because the highest-value review unit is the one that checks code against a contract written before the code, and without this phase there is nothing to check against.

1. Read the brief and the record. **Do not re-derive intent** — quote `## Intent`. Answered questions arrive in the brief and are binding.
2. **Acceptance criteria first, before any step list.** 2–6, each phrased so a test could assert it. They precede the plan because they are what implementation is graded against.
3. Ordered steps, each naming the files to touch, what changes, and the verification command **taken by name from `brief.toolchain`** — never invented.
4. Bugfix shape, kept verbatim from source A: documented root cause, then exactly three tasks — write the failing regression test, implement the fix, re-run the neighbouring tests — with the regression test's target file named.
5. Risk classification, here and not at ship: schema migrations, breaking API changes, auth/authz changes, production config, dependency upgrades, destructive data operations, new secrets. Source A's *"Require Human Approval For"* list becomes `risk.flagged`. **It must be set at planning**, because `PipelineEngine#gate_required?` only fires for `next_state ∈ {implementation, testing, deployment}` (`pipeline_engine.rb:161`) — setting it at deployment gates nothing, since deployment's `next_state` is `"done"` and `Ticket::PHASES.include?("done")` is false. All three designs got this wrong; two critiques caught it.
6. `change` is `null` unless `openspec/` already exists in the repo and you created a change in it. **openspec is opportunistic.**
7. Size: prefer one ticket. Split via `additional_tickets` only when parts are independently shippable.
8. Write `contract.json` and stop. barad_dûr validates it (§7, B5) and fails the run if it is malformed.

**Inputs.** Everything investigation had, plus `record.md` (`## Intent`, `## Findings`), plus `degraded[]` — if it contains `"findings"`, do a compressed 10-minute survey first and say so in `## Plan`.

**Artifacts.** `record.md` `## Plan`; `contract.json`:
```json
{"_v":1,"code":"ALG-42","base_sha":"9f2c1e…",
 "criteria":[{"id":1,"text":"<verbatim, untruncated>"}],
 "impact":["app/services/enrolment.rb","spec/services/enrolment_spec.rb"],
 "frozen_tests":{"spec/services/enrolment_spec.rb":"e3b0c44298fc…"},
 "risk":{"flagged":true,"reasons":["auth"]}}
```

**Returns.**
```json
{"_c":"planning.v1","change":null,
 "summary":"…","technical_notes":"…",
 "acceptance_criteria":["…"],"depends_on":[],"additional_tickets":[],
 "risk":{"flagged":true,"reasons":["auth"]}}
```
`risk` is nested, not a top-level `risky`, because `PLANNING_CONTRACT` already ships `additional_tickets: [{…,"risky":false}]` and `create_split_tickets` reads `extra["risky"]` — two same-named keys at two nesting levels in one example is a reliable way to get one of them dropped.

**Subagents.** None. Deliberately no planner-vs-critic debate: Smit et al. (ICML 2024) found MAD does not reliably beat self-consistency, and Yao et al. measured 27.46–86.36% disagreement collapse with r=0.902 between sycophancy and abandoning a correct position. A Ruby validator costs one method and cannot be talked out of its verdict.

---

### 4.3 Implementation — `/apply`

**Invocation.** `/apply ALG-42: …` + header. No JSON contract appended today; Sammath adds one. Budget: 150 / 3600 / $6.00. barad_dûr has already checked out `pipe/alg-42`.

**Responsibility.**

1. Read the brief, `contract.json` and `## Plan`. If `feedback` is present it is the top of the work list; also read `## Review`'s refuted list and **do not re-fix findings that were already killed with evidence**.
2. Work the plan in order. One focused commit per step, `git -C $REPO_PATH add -- <paths>` then commit, message prefixed with the ticket code. Never `git add -A`. Never touch the default branch.
3. **Test-first, and structurally verifiable.** For each scenario, the test commit precedes the implementing commit as a *separate commit*. Source A's guard survives verbatim in spirit — *"Do NOT fix the bug yet — only write the failing test"* — but enforced as commit ordering, which review and testing can check from `git log` rather than trust. This is the single highest-value line in either source given the 21.8–33.0% test-overfitting evidence.
4. **Never modify a file listed in `contract.json.frozen_tests`.** Never add a skip, `it.only`, `fdescribe`, `@pytest.mark.skip` or `t.Skip`. Barad_dûr checks the digests independently after this phase (§7, N10) — this is not a promise you are trusted on.
5. Run only the **targeted** checks from `brief.toolchain`: lint on changed files, the nearest test file. Source A's division of labour is kept verbatim in intent — *"Do NOT run the full test suite — that is handled by test-runner in the verification phase"* — because it is what keeps this phase inside 150 turns and keeps phase 5 a genuine regression gate.
6. Self-check before finishing — source A's Phase 5.5 **intent, not its mechanism**. Five checks, each naming an artifact: every acceptance criterion has an implementing code path (name it); every new branch has a test (name it); no debug leftovers or secrets in added lines; nothing deleted that is still referenced (grep it); the diff contains nothing the plan did not ask for. The 0.0–1.0 scores with a 0.6 floor are dropped — source A's own risk list concedes *"an implementation agent grading its own work will rarely fail itself,"* Huang et al. (ICLR 2024) show intrinsic self-correction degrades reasoning, and Kamoi et al. (TACL 2024) find self-correction works *only* with reliable external feedback. Exit statuses replace scores.
7. Commit `.pipe/<CODE>/` with the final commit, so the record rides the branch to the PR.

**Inputs.** brief (`branch`, `base_sha`, `feedback`, `is_rework`, `rework_count`, `toolchain`), `contract.json`, `## Plan`, `## Findings`, `## Review` on rework.

**Artifacts.** Commits on `pipe/<code>`, test commits ordered before fix commits, `record.md` `## Changes`.

**Returns.**
```json
{"_c":"implementation.v1",
 "files_changed":["app/services/enrolment.rb","spec/services/enrolment_spec.rb"],
 "commits":["a1b2c3d test(ALG-42): retry exhaustion returns 429"],
 "criteria_addressed":[{"id":1,"path":"app/services/enrolment.rb:88"}],
 "gate":{"lint":"pass","targeted_tests":"12 passed 0 failed"},
 "deviations":[{"from_plan":"step 4","why":"the column already existed"}]}
```
`deviations` exists because MAST measures "disobey task specification" at 11.0%; making deviation reporting explicit and cheap is how you stop it being silent.

**Subagents.** None. Source A's backend-dev/frontend-dev split is a Rails+HAML stack assumption with no meaning in an arbitrary repo, barad_dûr has one Builder slot, and Anthropic is explicit that *"most coding tasks involve fewer truly parallelizable tasks than research."*

---

### 4.4 Review — `/review`

**Invocation.** `/review ALG-42: …` + header + the new `REVIEW_CONTRACT`. Budget: **250 turns / 5400s / $8.00** — and `sweep_stale_runs!` must respect the per-run limit or a long review is marked dead while still working (`pipeline_engine.rb:123` uses the global `CLAUDE_TIMEOUT` today).

**Responsibility.** Source B's protocol, budget-fitted, execution-grounded, and with one deliberate divergence from source B on fixes. The coordinator scopes, dispatches, verifies adversarially, classifies and reports. **It reviews nothing itself and fixes nothing.**

**Step 0 — Intent.** Read `## Intent` and `contract.json` verbatim. Pass the intent text *and the artifact paths* into every subagent prompt so agents can bypass the coordinator's compression — source B's rule, and the reason Step 0 exists at all: *"A review with the wrong premise produces confident, wrong findings, and it produces them in several reviewers at once."* If `degraded[]` contains `"intent"`, say so and mark every intent-dependent finding **unverified against intent**.

**Step 1 — Scope.** `brief.base_sha` is the base; `git -C $REPO_PATH status --porcelain` first, because untracked files are invisible to `git diff` and must be routed explicitly as units with a read-from-disk instruction — source B calls this the main path, not an edge case. State the diff definition used (`<base>...HEAD` vs `<base>`) in the report. Classify each file new/modified/deleted/generated. **State the skip list; never skip silently.** `.pipe/**` is never a review unit.

**Step 2 — unit-00 first, and it EXECUTES.** This is the deliberate reordering, and it is the best-supported decision in the design: SWE-Review found **reproducer execution is the single strongest cross-model predictor of reviewer decision accuracy**, and Kamoi et al. found *zero* successful demonstrations of self-correction from prompted-LLM feedback outside tasks with reliable external feedback. A reviewer that reads a diff and opines is in the regime with no positive results. So unit-00:
- Runs `brief.toolchain.lint` and `brief.toolchain.test` scoped to the changed files. **A dimension whose entry is `null` reports `no-tooling-detected`; a dimension whose entry has `"runnable": false` reports `unavailable`. Neither is ever a pass.** Source B's rule *"mark pass only if every applicable cell is green"* trivially succeeds when no cell applies — that hole is closed explicitly.
- Verifies **test-first commit ordering** from `git log` and reports violations.
- Reproduces every measured claim `## Changes` asserts, **by the production entrypoint**, naming the entrypoint and how each argument was obtained, reporting the number *it* observed. Never rounds toward the implementer's figure. Never disturbs the working tree — no `git stash`, no `checkout`; use `git show <base>:<path>` into a temp dir or a detached worktree.

**Step 3 — Per-unit passes, capped by measured diff size** (from `brief.files_changed`, not from a keyword guess): ≤3 files → review inline, no unit agents; 4–15 → ≤3 units; >15 → ≤5 units grouped by directory, and say in the report what you did not reach. Kept from source B: **a source file and its spec are one unit**; **the same change repeated across files is one consistency unit** whose highest-value output is a call site that should have received the change and did not, found by grepping files the diff never touched — *"a per-file split structurally cannot find a missed call site, because the missed file is not in the diff"*; and a **criteria-conformance unit** that checks each `contract.json` criterion against an independently grepped implementing code path, treating "tests pass" as zero evidence. That last is the most valuable unit in the phase and here it always exists, because planning always writes a contract.

Source B's 25 units / waves of 8 / 17–20 agents is dropped. A real run at that scale is 60–130 minutes serialized, and the live probe confirmed parallel `Agent` dispatch in `-p` is **model-elective, not harness-guaranteed** (three requested parallel agents dispatched as three separate messages). Emit all `Agent` calls in a single message anyway; tolerate serialization; state the cap as a *Method deviation*, never as a silent coverage drop.

**Step 4 — Adversarial verification.** One `review-verifier` per Critical/High finding, batched per unit below that, **hard-capped at 4**. Posture verbatim from source B: *"Try to prove this finding WRONG. Default to REFUTED when you are not certain."* Six refutation routes, unchanged: pre-existing and not made worse (`git log -L` / blame); three or more places do it deliberately (grep and show them); the stated failure cannot occur (trace the path); the fix is different rather than better; the claim rests on a file/method/constant that does not exist (grep it — *"a fabricated reference refutes the finding outright, and say so plainly, because that is a signal about the whole category"*); already refuted with evidence in a prior round and the code has not changed. On STANDS the verifier must **correct any wrong detail** — mechanism, blast radius, affected population, implied severity — *"a finding that survives with a wrong mechanism attached is worse than one that gets dropped, because someone will confidently fix the wrong thing."* Tie-breaker mode reads the source in full and rules for one side; averaging is not an option, and the losing claim's evidence must be explained.

**Step 5 — Severity.** `references/severity.md` ships four Critical and nine High anchors as language-neutral *shapes*, **each conditional on a detected precondition, and the report must state which anchors were in force this run.** Critique 1 caught that four of six of Grond's re-authored High anchors ("hardcoded copy where the project routes copy through i18n", "a new env var absent from the example env file", "generated output failing its own generator's validator", "a new column absent from the change-notification path") are dead in a repo with no i18n, no `.env.example`, no codegen — collapsing the High tier toward Medium. Three universal High anchors are added: a public function whose new error path has no caller handling it; a changed serialization format with no version guard; a new dependency with no lockfile entry. Convention findings must cite the adoption rate of the **narrowest comparable construct** — *"if the narrow rate is below half, conforming to the neighbours is the correct call and there is no finding"* — and **cap at Medium** unless the rule is documented in `brief.repo_conventions` or a lint config. Source B's anti-rationalisation check ships verbatim.

**Step 6 — Report.** `<repo>/.pipe/<CODE>/review-r<N>.md`, never overwriting. Header carries base, diff definition, files reviewed / units, skip list with reasons, method deviations, **the intent premise given to the reviewers** so a reader can check it, and which severity anchors were in force. Per-category health table with precision = `stands/(stands+refuted)` over **verified findings only**; unverified items never enter the numerator; Polish labelled "not individually verified" every time; then `Verified OK`, `Refuted findings` with the evidence that killed them, `Needs a decision, not an edit`, and `Calibration notes`. `refuted.json` is written for the next round.

**Step 7 — One bounded fix pass.** Confirmed Critical and High **mechanical** findings are fixed by a fresh `fixer` subagent given the finding text and nothing else — never by the coordinator, and never by an agent that raised the finding. Then unit-00's checks re-run once. Exactly one round. Everything Medium and below goes to the report and into `feedback`. Source B's coordinator never fixes; barad_dûr's built-in tells the reviewer to fix its own findings. Both are wrong here: source B's real reports carry a `⚠ Conflict-of-interest disclosure` for precisely the case that is *normal* in this pipeline, and Panickssery et al. established a causal self-recognition→self-preference link.

**Inputs.** brief (`base_sha`, `files_changed`, `untracked`, `toolchain`, `repo_conventions`), `contract.json`, `## Intent`, `## Plan`, `## Changes`, prior `refuted.json`. **Explicitly not given: the implementation phase's reasoning or transcript.** Anthropic: *"A reviewer running in a fresh subagent context sees only the diff and the criteria you give it, not the reasoning that produced the change."* Also explicitly not given: `ticket.feedback` — see §7, N8.

**Returns.**
```json
{"_c":"review.v1","verdict":"changes_requested",
 "report":"/workspace/core/.pipe/ALG-42/review-r1.md",
 "findings":{"critical":0,"high":1,"medium":3,"polish":4},
 "categories":[{"name":"correctness","raised":3,"refuted":1,"stands":2}],
 "criteria":[{"id":1,"verdict":"satisfied","path":"app/services/enrolment.rb:88"},
             {"id":2,"verdict":"not_satisfied","path":null}],
 "executed":{"lint":"pass","tests":"12 passed 0 failed","types":"no-tooling-detected"},
 "decisions_needed":["retry budget is a product call, not an edit"],
 "feedback":"<structured defect text for the implementer>"}
```
`feedback` is structured diagnosis, not a verdict, because SWE-Review's information-gradient ablation measured verdict-only review at 8% resolve rate vs 21% for structured diagnosis vs 32% oracle, against a 3% no-review baseline. Also written to `review.out.json` as it is produced, so a turn-limit death does not discard it.

**Subagents.** `review-unit` ×0–5, `review-verifier` ×≤4, `fixer` ×≤1. Worst case **10 agents**, typical 4. All three review agents carry `model: sonnet` in frontmatter — source B pinned them deliberately, and letting them inherit the orchestrator model is a 5–10× unit-cost regression on the most fan-out-heavy phase in the pipeline.

---

### 4.5 Testing — `/test`

**Invocation.** `/test ALG-42: …` + header + the extended `TESTING_CONTRACT`. Budget: 100 / 3600 / $4.00.

**Responsibility.** Not the first execution — review already ran lint and the targeted subset. This is full-suite regression, per-criterion verification, and mechanical anti-reward-hacking enforcement. It is the last always-on phase, so it also owns the record-truth verdict.

1. Use `brief.toolchain`. If an entry is `null` or `runnable: false`, do **not** invent a command; report the dimension as `no-tooling-detected` or `unavailable`. barad_dûr's existing built-in text ships nearly verbatim: *"Look for the commands in the places projects keep them — package.json scripts, Rakefile, Makefile, tox.ini, CI workflow files, CONTRIBUTING — rather than guessing. Do not invent a command that does not exist."*
2. Run in order, reporting each suite separately **including the ones not run and why**: lint/format → typecheck → unit → integration/regression → e2e.
3. **Per-criterion verification.** For each criterion in `contract.json`, name the test that exercises it and its result: `satisfied | not_satisfied | untestable`. This is the one thing barad_dûr's contract lacks and source A's test-runner has, and it is the phase's highest-value output.
4. **Record-truth verdict** — source B's sync-readiness generalised off OpenSpec, moved here from deployment because deployment is off by default (`Features::PHASE_DEFAULTS["deployment"] => false`) and all three designs put load-bearing gates in a phase that never runs. Three ways: criteria satisfied by code *and* covered by a passing test; criteria not satisfied, with which side you believe is wrong; **behaviour that shipped but appears in no criterion** — the contract is incomplete, say so. Cross-check `contract.json.impact` against the diff both directions: in impact but not the diff = incomplete or stale; in the diff but not impact = scope creep.
5. Reproduce any measured claim `## Changes` or `## Review` asserts, through the project's own entrypoint. Report the number *you* observed. If you built the harness yourself, say so.
6. Fix failures caused by this ticket and commit them, **in non-test code only**. Confirm a failure is pre-existing by running it at `base_sha` in a detached `git worktree` — never `git stash`, never check another branch out in the working tree; it is what is under review. A pre-existing test that genuinely must change becomes a `decisions_needed` item, never a fix.
7. **Never weaken, skip, delete or rewrite a test to make it pass, and never mark a suite green that you did not run.** barad_dûr verifies this independently with digests after the run.

**Inputs.** brief (`toolchain`, `base_sha`, `feedback` on rework), `contract.json`, `## Plan`, `## Changes`, `## Review`, the review report path.

**Returns.**
```json
{"_c":"testing.v1","executed":true,
 "command":"bundle exec rspec","passed":128,"failed":0,
 "suites":[{"kind":"lint","command":"bundle exec standardrb","passed":1,"failed":0},
           {"kind":"unit","command":"bundle exec rspec","passed":128,"failed":0},
           {"kind":"e2e","command":null,"skipped":"no e2e runner in this repo"}],
 "criteria":[{"id":1,"verdict":"satisfied","test":"spec/services/enrolment_spec.rb:41"},
             {"id":2,"verdict":"untestable","test":null}],
 "record_truth":{"satisfied":1,"not_satisfied":0,"unspecified_behaviour":1}}
```
`"executed": false` when nothing could run. That is the fix for the silent-green-PR bug: `capture_test_results` no longer returns early on missing counts, and `PushPrJob` drafts on `!executed` as well as on failures.

**Subagents.** None. The phase is already an isolated process, so a "keep verbose output out of context" subagent buys nothing. An LLM judge here would add sycophancy surface and no signal — the suite is already reliable external feedback.

---

### 4.6 Deployment — `/ship`

**Invocation.** `/ship ALG-42: …` + header + the new `DEPLOY_CONTRACT`. Budget: 40 / 900 / $1.00. **Off by default**; when off, the ticket parks at the verdict gate after testing and `PushPrJob` opens the PR — which is the intended shape, and why nothing load-bearing lives here.

**Responsibility.** Neither source has a ship step; this is authored fresh from barad_dûr's own Shipper prompt plus the portable half of source B's pre-commit hygiene unit.

1. **Hygiene gate.** Classify every remaining untracked file by **reading its content, never by its name** — source B's rule, and the one that actually matters (*"A file named `*_spec.rb` can still be a scratch file"*). Assert no `.env` or credential file is staged; no debug leftovers in added lines; lockfile changes have a matching manifest change; new env vars appear in the repo's example env file **if it has one**; new executables are mode 755 **if the repo has other executables**. Every check is conditional on the repo actually having the thing — that conditionality is the portability.
2. **Changelog, conditionally.** If the repo has a changelog file or a fragment directory, read its top 40 lines and add an entry in the format it already uses. **If it has neither, do not create one** — write the release note into `## Ship` instead. barad_dûr's current built-in unconditionally creates `CHANGELOG.md`, which is wrong in most repos.
3. Write a 3–6 line release note derived from the record: what changed, why, risk flags, verification status, what is left undone. It becomes the PR body.
4. **If review or testing falsified a claim written into this ticket's own artifacts, correct the artifact and say so.** A false measured claim outlives the branch and every later reader inherits it.
5. Commit. **Never push, tag, merge or deploy** — `LandWork`, `PushPrJob` and `BranchMerger` own that, and the house rules forbid it at the harness level too.

**Inputs.** brief, the whole record, `contract.json`, the review report, the testing JSON.

**Returns.**
```json
{"_c":"deployment.v1","changelog":true,"release_note":"…",
 "hygiene":{"blocking":[]},"unverified_claims":[]}
```
`hygiene.blocking` non-empty forces a gate.

**Subagents.** None — every step is a deterministic check or a derivation from the record.

---

## 5. How state survives

Five mechanisms, in descending order of how much weight they carry.

**1. The brief — Ruby's channel, one direction, authoritative.** `PhaseBrief.write!(ticket, phase, repo_path)` runs inside `ClaudeCodeRunner#execute` before `PhasePrompts.execution`, writing `<repo>/.pipe/<CODE>.brief.json` (gitignored — it contains no history and would churn the diff). It carries the full schema in §3, and three fields that only Ruby can produce honestly:

- `toolchain` — discovered by Ruby from `package.json` scripts, Makefile targets, Rakefile tasks, `pyproject.toml`/`tox.ini`/`noxfile.py`, `composer.json`, `go.mod`, `Cargo.toml`, `.github/workflows/*`, and `CONTRIBUTING`; each entry records the command, where it was found, **and whether its binary resolves on `PATH`** (`runnable`). Cached per repo, invalidated on manifest digest change. Both Forge designs made a prior LLM phase write the toolchain and four later phases read it with no recovery rule — so switching investigation off, or having it die at turn 120, silently turns review's execute-before-opining into a no-op. Toolchain discovery is file parsing, not LLM work.
- `repo_conventions` — the target repo's `CLAUDE.md`/`AGENTS.md`/`CONTRIBUTING`, inlined (capped at 8 KB total). Because cwd is the harness, these never auto-load, and only one of the six phases would otherwise ever read them.
- `degraded` — computed by `PhaseRecord.sections(repo, code)`, a ~30-line Ruby parser that checks each required upstream heading exists and is non-empty. Missing sections are named in the brief so the skill must acknowledge them rather than choose to; for **planning and implementation**, a missing prerequisite fails the run with an Event instead of proceeding on a hole.

**2. The record — the agents' channel, append-only by convention, seven headings, one owner each.** `<repo>/.pipe/<CODE>/record.md`, committed to `pipe/<code>` by implementation, so it rides the branch into the PR the human approves. A phase creates the file with all seven headings if missing and writes only its own. Excluded from `capture_diff` and from review's scope so the harness never reviews itself.

**3. The frozen contract — `contract.json`.** Written once by planning, read by implementation, review and testing, never rewritten. Holds the **untruncated** criteria (the ticket column truncates each to 200 chars and caps at 8 — a GIVEN/WHEN/THEN clause routinely exceeds that, and review would otherwise be checking against silently clipped contract text), the impact file list, `base_sha`, and `git hash-object` digests of every existing test file. It is the anchor for per-criterion conformance in review, per-criterion verification in testing, and the tamper check in Ruby.

**4. The out-files — every contract JSON, written to disk *as well as* to the final message.** `<repo>/.pipe/<CODE>/<phase>.out.json`. `handle_structured_output` prefers the final message, falls back to the file, **and runs even when `result.ok == false`**. This is the fix for the class of failure all three critiques flagged: a review that dispatched five agents, wrote its report and died at turn 249 currently produces nothing barad_dûr can see, while the report and the fix commits sit on disk.

**5. The database — answered questions, feedback, criteria, risk.** `Question.where(ticket_code:, status: "answered")` is rendered into `brief.answered_questions[]` as `{q, chosen}`. `ticket.feedback` reaches implementation (and testing on rework), never review. `ticket.risky` is set from planning's `risk.flagged`, in time for `gate_required?` to use it.

Contract-parse robustness: every contract carries a `"_c": "<phase>.v1"` sentinel, and `StructuredOutput.json_block(text, expect:)` prefers the last fenced block carrying that key, falling back to current behaviour. A live probe confirmed models volunteer unrequested ```json blocks; review and ship both emit long reports full of code fences, and `.last` currently wins.

---

## 6. What comes from each source, and what is dropped

### From source A (`agentic_development_workflow`)

**Kept, near-verbatim.** The bugfix branch entire — the literal keyword list for task-type detection, the error-string grep, the root-cause-with-evidence requirement, the fixed three-task plan shape, and the two-step *"Do NOT fix the bug yet"* ordering, generalised into commit ordering so it is checkable rather than asserted. The targeted-vs-full test division (*"Do NOT run the full test suite — that is handled by test-runner in the verification phase"*), which is what keeps implementation inside its turn budget and keeps testing an honest regression gate. Phase 1's investigation recipe, with every `knowledge/**` path replaced by `brief.repo_conventions` and repo-discovered equivalents. `/research`'s per-service fan-out prompt with its five-part report schema, its *"Summarize — don't dump raw content"* rule, and its bounded gap-analysis round. The `>10-task` decomposition offer → `additional_tickets`, its already-existing headless descendant. The question framework's applicability matrix, compressed into a selector. The Forbidden Actions and "Require Human Approval For" lists — the first into `harness/CLAUDE.md`, the second into planning's risk classifier.

**Kept in intent, replaced in mechanism.** Phase 5.5's self-evaluation: five artifact-naming checks instead of five 0.0–1.0 scores with a 0.6 floor. Dropped because it is unfalsifiable by construction, because source A's own risk list concedes it, and because Huang et al. (ICLR 2024) and Kamoi et al. (TACL 2024) both say intrinsic self-correction without external feedback does not work. The context file → the record, cut from a 117-line template with a metadata table, Progress table and session counter down to seven headings. Source A's own *"CRITICAL: update ALL metadata fields"* rule exists only because a resumed in-process session had nowhere else to look; `PhaseRun` rows already are the ledger, and duplicating live state is the drift bug, not the feature.

**Dropped.** The six blocking `STOP AND WAIT` gates — `AskUserQuestion` is verifiably absent from the tool list in `-p` (probe: *"The AskUserQuestion tool does not exist or is not accessible in this session"*), so a port that kept them would either stall to the 45-minute timeout or silently invent the human's answers, the second being the dangerous failure. Replaced by 0–2 async `Question` rows and recorded assumptions. The `knowledge/` corpus in every form — unfilled scaffolds that agents fabricate content to fill, `../services/{service}/` hardcoded in *executable agent prompts* not just docs, and a write side that is unwired even in the source repo. `/update-knowledge` and `/improve` — the first is explicitly single-writer per its own warning and a board running five tickets violates it by construction; the second rewrites `.claude/agents/*.md`, exactly what `Harness.scan` reads and `AgentRoster.rebuild!` turns into the live roster, so an unattended run can change the roster underneath in-flight tickets with no rollback. **No learning loop at all**, not even a stamped flag: source A's `optimization_tips.md` and `discovered_patterns.jsonl` are written by the loop and read by nothing, and deployment being off by default means any write side we added would be dark while its read side polled an empty file forever. Capture without consumption is pure cost. The persisted S/M/L/XL complexity field — it silently controls five downstream behaviours, degrades to "Standard everywhere" the moment one phase forgets to branch, and is decided from the *title* before any code is read, then spends money on it (a ticket titled "cross-service architecture cleanup" touching one file would buy six investigators). Replaced by depth scaling from `brief.files_changed`, which Ruby measures. The compliance-checker — it ships as literal `TODO` placeholders and fires on every task; MSR'26 found 92.31% of examined code-review agents averaged below 60% signal ratio, with only *specialised* security bots scoring well. The Implementation Report's five extraction rules — they feed a learning loop that does not exist here; the release note covers the PR-facing half.

### From source B (`quant_development` review skill)

**Kept, near-verbatim — this is the backbone of `/review`.** The six design rules, reproduced in the skill's rationale section, especially rule 1 (no self-review; *"a one-file diff still gets one fresh agent"*) and rule 5 (**agreement is not evidence** — convergence raises the priority of *verifying* a finding, not confidence in it), which is repeated in three places on purpose because it is the one most likely to be optimised away. Step 0's poisoned-premise theory entire, promoted out of review into investigation because barad_dûr *has* an investigation phase and source B's own OpenSpec path shows the right move: consume the pre-written intent artifact rather than re-derive it. Step 1's scoping mechanics: untracked files as the main path, the explicit and reported diff definition, the stated skip list. The unit grouping rules: source-plus-its-spec, and the consistency unit whose highest-value output is the missed call site. unit-00 as the only command-executing unit, and its measurement-reproduction dimension with the anti-contamination warning (*"matching a wrong number because you reused the author's wrong harness … converts an unverified claim into a double-confirmed one"*) and the absolute never-disturb-the-working-tree rule. The whole adversarial verifier: REFUTED by default, the six refutation routes, the STANDS-must-correct obligation, tie-breaker mode with its ban on averaging and its requirement to explain the losing claim, the prior-refuted list as cross-round memory. Both evidence bars. The anti-rationalisation checklist. Per-category precision as `stands/(stands+refuted)` over verified findings only, Polish labelled not-individually-verified every time, never overwriting an earlier round, `Needs a decision, not an edit`, and `Calibration notes`. The hygiene unit's *"decided by READING ITS CONTENT, never by its name."* Sync-readiness → the record-truth verdict.

**Changed deliberately.** The OpenSpec layer is **retargeted, not kept and not dropped**. Grond kept it by mandating a non-null `change` and writing `openspec/changes/<code>-plan.md` into every repo — which pollutes repos that never asked for it, and whose claim of `SpecSync` compatibility I checked and found **false**: `spec_sync.rb#spec_targets` scans only `<repo>/openspec/specs/<capability>/spec.md`, never `changes/**/specs/`, so the Capabilities UI does not light up. Sammath substitutes artifacts of equal standing: the delta spec's SHALLs → `contract.json.criteria`; `#### Scenario:` → test mapping → criterion → test mapping; `tasks.md` `[x]` honesty → the criteria-conformance unit; `## Impact` cross-check → `contract.json.impact` cross-check, bidirectionally; `openspec validate --strict` → Ruby's contract validation; the sync verdict → the record-truth verdict. `change` stays in the planning contract and is emitted only if `openspec/` already exists.

The dispatch scale is cut from 25 units / waves of 8 / 17–20 agents to a diff-size-scaled ≤5 units and ≤4 verifiers, capped at ~10 agents. The cap and its reason go in the report's *Method deviations* line, never as a silent coverage drop. The static repo→tool matrix becomes `brief.toolchain` with the trivial-pass hole closed. The `knowledge/conventions/` corpus that defines the High-vs-Medium boundary becomes optional, with the degradation stated: convention findings cap at Medium and the report says which regime it ran in. Absolute paths, the fixed sibling-repo list and `origin/master` become `brief.repo_path` and `brief.base_branch`. The severity anchors are re-authored as conditional language-neutral shapes; the report states which were in force.

**Added, against source B.** A single `fixer` subagent for confirmed Critical/High mechanical findings. Source B's coordinator fixes nothing, and its real reports still carry conflict-of-interest disclosures, because in this pipeline review runs immediately after implementation as the *normal* case. A fresh agent that saw neither the code's reasoning nor the finding's reasoning is the structural version of the promise.

---

## 7. What barad_dûr must change

Six blocking, eleven follow-on. Every one is small and localised, and the first six are worth doing on their own merits.

### Blocking

**B1 — `PhaseBrief`.** New service `app/services/phase_brief.rb` plus `app/services/toolchain.rb` and `app/services/phase_record.rb`. Called from `ClaudeCodeRunner#execute` before `PhasePrompts.execution`; writes the brief and, on first use, `<repo>/.pipe/.gitignore` containing `*.brief.json` and `*.out.json`. Fields per §3. `Toolchain.detect(repo_path, scope)` parses the manifests, resolves each binary against `PATH`, caches per repo keyed on manifest digests. `PhaseRecord.sections(repo, code)` returns which headings exist and are non-empty; the result becomes `degraded[]`, and for planning and implementation an empty prerequisite fails the run with an Event rather than proceeding.

**B2 — ship and resolve the bundled harness.** `Harness::BUILTIN = scan({name: "sammath", path: ENV["HARNESS_DIR"].presence || "/opt/barad-dur/harness"})`, memoized; Dockerfile gains `COPY harness/ /opt/barad-dur/harness/`; dev falls back to `Rails.root.join("harness")` with a one-time warning Event. New `Harness.source_for(phase, setting) → [invocation, info]`: try the user harness's `PHASE_CANDIDATES` first, fall back to BUILTIN's (`explore|propose|apply|review|test|ship` always match). `active?` returns true for BUILTIN **regardless of `fw`**, with a data migration flipping `setup["fw"] == "2"` realms to `"1"` and an Event announcing the reinterpretation — `active?` is currently `setup["fw"] != "2" && detect.present?`, so a realm that chose vanilla would otherwise resolve `invocation = nil` on every phase. `setup["map:<phase>"] == "built-in"` keeps working and now means "use the shipped harness for this phase"; emit an Event when a realm is reinterpreted.

**B3 — prompt shape.** `harness_prompt` gains the three-line `BARAD-DUR-*` header. The argument becomes `"#{ticket.code}: #{ticket.title}"` for **every** phase — today implementation passes the bare change slug, so ticket identity vanishes from the prompt. Delete the `(phase != "implementation" || change_ref(ticket).present?)` gate in `execution`: without it, a repo with no openspec gets no harness implementation at all, which is the single hardest requirement in this brief. Change *"delegation via the Task tool"* to name both `Agent` and `Task` (the documented name is `Agent`; `system/init` still advertises `Task`; both resolve).

**B4 — branch lifecycle.** `prepare_branch` runs on the **first enabled phase** for the ticket, not only implementation, and never uses `-B`:
```ruby
unless git?(repo, "rev-parse", "--verify", branch)
  git?(repo, "checkout", "-b", branch, base)
end
git?(repo, "checkout", branch)
```
`-B` resets the branch to current HEAD, so a retry after a `BranchMerger` conflict (which leaves HEAD on base) silently discards every implementation commit — and running it on six phases instead of one multiplies the exposure sixfold. Resolve `base` once, shared with `capture_diff` and `BranchMerger`, from `origin/HEAD` then `main` then `master` then the current branch.

**B5 — contracts.** Add `IMPLEMENTATION_CONTRACT`, `REVIEW_CONTRACT`, `DEPLOY_CONTRACT` to `PhasePrompts`; extend `TESTING_CONTRACT` with `executed`, `criteria[]`. Wire all six into `contract_for` and `handle_structured_output`. Add the `_c` sentinel to `StructuredOutput.json_block(text, expect:)`. Read `<repo>/.pipe/<CODE>/<phase>.out.json` as a fallback, **and run `handle_structured_output` on the failed-run path too** — currently `execute` skips both `capture_outputs` and `handle_structured_output` when `result.ok == false`, discarding work that succeeded. Validate: planning must produce a parseable `contract.json` with ≥1 criterion or the run fails.

**B6 — "nothing ran" must not look green.** Drop the `return unless data.key?("passed") || data.key?("failed")` guard in `capture_test_results`; persist `executed` and `criteria` (two new `phase_runs` columns: `tests_executed` boolean, `criteria_results` jsonb). Add `Ticket#verification_red?` = `tests_failed? || !tests_executed? || criteria_unsatisfied?`. `PushPrJob` uses it for `draft` and the `[tests failing]` prefix (widen the prefix to `[unverified]` when nothing ran). Without this, `PushPrJob` opens a normal PR on a repo where no suite exists, indistinguishable from a fully green one.

### Follow-on

**N7 — `capture_diff`.** Merge-base against the resolved base, `<base>...HEAD`, include untracked files, and `':(exclude).pipe/'` so the record does not eat the drawer's 40-line preview.

**N8 — feedback routing.** `%w[implementation review]` → `%w[implementation testing]` in both `harness_prompt` and `build`. Feedback is for the implementer; injecting it into the review prompt poisons a re-run of review, which is what makes the backward edge (N11) safe.

**N9 — budgets.** `PhasePrompts.execution` returns `max_turns`, `timeout`, `max_cost_usd` per phase (values in §4). `ClaudeCodeRunner` passes the first two to `HeadlessAgent.call` — which already accepts them and is never given them — and persists them on the run. `sweep_stale_runs!` uses the per-run limit, not the global `CLAUDE_TIMEOUT`, or a long review is swept as dead while still working. Add a mid-run cost ceiling checked in the `on_message` callback (cost is already streamed); SIGTERM on breach and read the on-disk out-file. Today `over_cap?` is checked only in `tick!` *before* pickup and `pause_for_cap!` merely sets `running: false`, so five concurrent reviews can blow the daily cap mid-flight with nothing to stop them.

**N10 — `TestGuard`, in Ruby.** Run inside `capture_outputs` after review and testing, independent of what the agent reported: compare `contract.json.frozen_tests` digests, count assertion-line deltas in pre-existing test files, grep the diff for added skip markers, detect deleted test files. On a hit: force a gate, emit a warn Event, and make the PR a draft. This is ~60 lines and it is the highest-value line of code in the proposal. Evidence: ImpossibleBench measured GPT-5 exploiting mutated tests **76%** of the time with stronger models cheating more; IBM measured **21.8% (Claude-3.7) / 33.0% (GPT-4o)** of patches passing generated tests failing hidden golden tests, *worsening* under iterative refinement — in a loop with an LLM critic deciding whether to modify code or tests, which is exactly this pipeline's review→test seam. "Never weaken a test" is advisory to a model; a `git hash-object` digest is not.

**N11 — the backward edge, capped at one.** On `verdict == "changes_requested"` with confirmed Criticals the fix pass could not close: write `ticket.feedback`, increment a new `tickets.rework_count`, re-enter implementation once, then gate. Without it a review that finds a Critical writes prose and the ticket advances. Capped at one because IBM measured overfitting *rising* under iterative refinement and Yao et al. measured sycophancy rising in later rounds.

**N12 — risk.** `apply_plan_output` reads `data.dig("risk","flagged")` → `ticket.risky`. Add `ticket.risky?` to `PipelineText.verdict_reason` so it surfaces on the verdict card even when autonomy is `off`.

**N13 — `child_env`.** Null `BUNDLE_DEPLOYMENT`, `BUNDLE_PATH`, `BUNDLE_WITHOUT`, `BUNDLE_GEMFILE`, `RAILS_ENV`. These are set as `ENV` in the Dockerfile's `base` stage and inherited by every child process, so a Ruby target repo's `bundle exec` picks up barad_dûr's own production, deployment-mode bundle. This is a real corruption path that none of the three designs mentioned.

**N14 — roster.** Widen `PHASE_AGENT_HINTS` to all six phases (`implementation => %w[builder fixer]`, `testing => %w[tester test-runner]`, `deployment => %w[shipper]`). `AgentRoster.rebuild!` must not rename the six defaults from BUILTIN's agent names, and `Harness.specialists` needs an `active?` guard so BUILTIN's agents don't appear for realms that opted out.

**N15 — criteria fidelity.** `apply_enrichment`: `.truncate(400)` and `.first(12)`. The ticket column is an index; `contract.json` is authoritative and untruncated, and every skill is told so.

**N16 — wizard.** Two framework options instead of three ("Sammath (shipped default)" / "Your repo's own harness"). Show, per phase, which source resolved it, so a half-mapped user harness is visible rather than mysterious. A configured-but-unresolvable `harness_dir` must be a **loud failure**, not a silent fall-through to whatever `.claude/` the user's own repo happens to have.

**N17 — evaluation.** `test/fixtures/harness/` with five ticket fixtures against `workspace/sample-app`, and `rake harness:bench[variant]` running built-in vs Sammath on the same tickets and the same model, reporting resolve/PR-quality, tokens, wall-clock and cost per phase. Anthropic's own recommended way to settle this is the with-skill/without-skill benchmark, and Martinez & Franch's leaderboard profiling is a null result on architecture class. This is one day of work and it is the only thing that can justify the other sixteen.

**Explicitly not changed.** The `STATES` enum and phase order. Reordering testing before review is the change the evidence most supports, and it touches the board, the UI, `Features`, `PipelineText` and the engine. Sammath compensates by making review execute the targeted subset itself and by making testing the always-on gate that owns per-criterion verdicts and record-truth. Also unchanged: `HeadlessAgent`'s parsing (no `--json-schema`, no `--resume`); `ArchiveChangeJob` and `SpecSync` (they no-op cleanly without a change ref, and Sammath does not pretend they fire).

---

## 8. Portability

A repo with no `knowledge/`, no `openspec/`, no test runner, on `develop` instead of `main`, in Go or Elixir.

**No `.claude/` is written into the user's repo.** The harness lives at `/opt/barad-dur/harness`, outside every git repository — so a `git` command missing its `-C` fails loudly instead of committing into barad_dûr's own source under `bypassPermissions`. The only footprint in the target repo is `<repo>/.pipe/`, created on demand, per ticket, with the brief and out-files gitignored and the record deliberately committed so the plan, the review and the verification ride the branch into the PR.

**No language, package manager, test runner or linter is named in any of the nineteen files.** `Toolchain.detect` reads the manifests, records what it found with provenance, and marks each entry `runnable` or not. Six phases read that. The house rule is absolute: *"Run no command that is not in `brief.toolchain`. If a category is `null`, write `no-tooling-detected`. If it is present but `runnable: false`, write `unavailable` and name the missing binary."*

**A repo with no tests at all** produces `"executed": false`, which forces a **draft PR and a gate** (B6). The review phase reports `no-tooling-detected` for every dimension and says so in the report header; convention findings cap at Medium; the criteria-conformance unit still runs, because it greps for implementing code paths rather than running anything. That is the honest degradation: the pipeline still produces a plan, a diff and a criteria-conformance table, and it tells you plainly that nothing was executed.

**A repo whose declared tools are not installed in the runner** — Python, Go, Rust, anything outside the shipped image, which carries only ruby, node/npm, git, gh, curl and postgresql-client, runs as `USER 1000:1000` with no package manager — is the sharpest portability limit and none of the three source designs mentioned it. `Toolchain` reports `runnable: false`, testing reports `executed: false`, the PR opens as a draft with `[unverified]`, and a warn Event names the missing binaries. **The pipeline degrades honestly instead of degrading into prose self-assessment.** The fix is a fatter runner image or exec'ing the repo's own devcontainer, and it is stage 4 of the plan, not a v1 requirement.

**No `knowledge/`, no `openspec/`, no `implement/`, no sibling `../services/`, no `INDEX.md`.** Repo conventions come from whichever of `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING` / `README` exists, capped at three files and 8 KB, inlined by Ruby. Their absence is handled by an explicit rule rather than by fabrication: undocumented convention findings cap at Medium, and the report states which regime it ran in. `openspec/` is written only if it already exists. The severity anchors are conditional on a detected precondition and the report lists which were in force.

**A repo on `develop` or `trunk`.** One base resolver — `origin/HEAD` → `main` → `master` → current branch — shared by `PhaseBrief`, `capture_diff`, `prepare_branch`, `BranchMerger` and the review skill. Today `capture_diff` falls back to `HEAD~1` (presenting one commit as "the change") and `BranchMerger` fails outright with *"no main/master branch"*.

**Monorepo sub-projects.** The brief carries `scope_path`; edits scope to it; `.pipe/` lives at the checkout root because the branch does. Note that `Workspace.repo_path("mono/apps/web")` returns the repo *root*, so `.pipe/` lands at the monorepo root regardless of scope — consistent with `capture_plan_artifact`, and stated rather than implied.

**Monorepo workspaces where `Workspace.root` *is* the ticket repo** get `.pipe/` inside the repo under review by construction. Handled by the `':(exclude).pipe/'` pathspec in `capture_diff` and by review's Step 1 classifier hard-skipping `.pipe/**`.

**Any phase can be switched off** and the rest still function, because `degraded[]` names what is missing: no `## Findings` → planning does a compressed survey and says so; no `## Plan` → review marks intent-dependent findings unverified and refuses to start if `contract.json` is absent; no testing → the PR opens with `executed: false`. Deployment off (the default) loses only the changelog and the release note — the record-truth verdict, per-criterion verification and risk classification all live in phases that always run.

---

## 9. Risks and open questions

**Nothing in the literature predicts this wins.** Martinez & Franch's leaderboard profiling is a null result: *"No single architecture consistently achieves state-of-the-art performance."* Agentless — a fixed three-phase pipeline with no reviewer and no planner — was competitive with far more complex agents at a fraction of the cost. Six phases is a hypothesis. N17 is how it gets tested, and it should ship first.

**Review's value shrinks exactly where this pipeline runs it.** SWE-Review measured reviewer decision accuracy at 89.4% on low-quality patches but **75.6% on high-quality ones**, and resolve-rate gain from review at **+25.1 points for the weakest generator and +3.0 for the strongest**. Sammath runs review immediately after a frontier-model implementer, on the same model family, on code it just wrote — the worst configuration on all three axes — and it is by far the most expensive phase. The design's answer is instrumentation, not faith: per-category raised/refuted/stands is persisted per ticket, so the phase can be switched off on evidence. **This is the number I would want measured before scaling.**

**Six one-shots is a serial reliability chain.** At 95% per-phase reliability, end-to-end is ~74%; at 90%, ~53%. Ord's half-life result is consistent with a constant per-unit failure hazard, so it compounds honestly. The split only pays if each boundary's gate catches more than the boundary's own handoff loss introduces — and MAST says handoff loss (41.8% specification issues) is the dominant term. Every mechanism in §5 is buying that term down. **If the gates get skipped, six phases is strictly worse than one.**

**`--permission-mode bypassPermissions` means every safety property is prompt- or hook-level, never capability-level.** Live probes confirmed: skill `allowed-tools` **grants and never restricts** — a skill declaring `allowed-tools: Read, Grep, Glob, Bash` successfully used `Write`. Agent `tools:` frontmatter *does* restrict (`WRITE=DENIED` observed), **but the same agent wrote a file via `echo >` because it had `Bash`** — and source B's own field report records a verifier running `git stash` mid-verification in violation of its agent definition. Sammath's verifier keeps `Bash` because refutation route 1 needs `git blame` and `git log -L`. The `PreToolUse` hook in `harness/.claude/settings.json` is a real mitigation but not a guarantee. **The only genuine enforcement in this design is barad_dûr's independent `TestGuard` (N10), which is precisely why it is not optional.** This is an unresolved gap across all three critiques.

**Parallel subagent dispatch is model-elective, not harness-guaranteed.** A live probe requesting three parallel agents got three separate messages, one call each. On a slower model, review serializes and can approach its 5400s budget. The diff-size cap, the unit-00-first ordering, the out-file fallback and the per-run sweep limit are mitigations, not guarantees.

**`.pipe/` is a real footprint in someone else's repo.** Committing the record buys traceability — the plan, the review and the verification reach the PR the human approves, which is the whole point of barad_dûr's verdict gate. A user who disagrees adds one line to `.gitignore` and everything still works, because review already treats untracked files as first-class — but that opt-out disables the feature's own justification, and should be described that way rather than as costless.

**Review runs before testing because the STATES enum says so.** The evidence most supports the opposite order. Review executing the targeted subset is a genuine mitigation, but it is partial: (a) the subset may be `no-tooling-detected`; (b) the tests it runs were written by `/apply` in the same pipeline — SWE-Review found **82% of false-approval reviews contained the keyword "pass"**; (c) the reviewer is the same model reading the record its own pipeline wrote. The frozen contract and the criteria-conformance unit with independently grepped code paths are the real countermeasures; "tests pass" is treated as zero evidence. Whether that is enough is open.

**A `contract.json` that validates but is wrong steers five phases confidently in the wrong direction.** That is the poisoned-premise failure at pipeline scale, and freezing the contract makes it worse, not better, when the freeze is wrong. The mitigation is the human control point after planning (below); the residual risk is real.

**Freezing test digests blocks legitimate test refactors.** A pre-existing test that genuinely must change becomes a `decisions_needed` item and costs a human round-trip. That is the intended price: the false-positive cost is a blocked refactor; the false-negative cost is a green pipeline shipping a patch that only passes tests it rewrote.

**Open question I am not resolving here: whether the human gate should move earlier.** MAST puts 41.8% of failures in specification and ~79% before verification; fixing a spec error at planning costs one phase, catching it at the terminal verdict gate costs six — and METR found developers were 19% slower with AI while believing they were 20% faster, which is the calibration a terminal gate on a large accumulated diff works against. An `autonomy: "plan"` mode gating only `ready_to_implement → implementation` is a two-line change to `gate_required?`. I have left it out of the seventeen because it changes the default operating experience and deserves its own decision, but it is the cheapest remaining safety improvement available.

**Concurrency remains the largest untouched hazard.** `MAX_IN_FLIGHT = 5`, one checkout per repo, no per-repo dedupe in either pickup path. B4 removes the `-B` data-loss bug and gives each ticket its branch from phase one, but two tickets in the same repo still race the working tree. Per-ticket `git worktree` is the real fix — CAID measured +25.6 on PaperBench and +14.7 on Commit0 from isolation plus a real merge mechanism — and it is stage 4. Until then, serialize pickup per repo.

---

## 10. Staged implementation plan

**Stage 0 — the eight Ruby bug fixes (2–3 days). Ship regardless of the harness verdict.**
N15 (criteria truncation), N7 (merge-base diff + `.pipe` exclusion), N8 (feedback routing), B4 (branch lifecycle, never `-B`), N13 (`child_env`), N9 (per-phase budgets + sweeper + mid-run cost ceiling), N12 (risk → `ticket.risky` at planning), plus the answered-questions read path from B1 injected into the *existing* built-in prompts. Every one of these is a live defect today, independently verifiable, and improves the built-ins with no harness present. The answered-questions fix alone is worth more than most of what follows.

**Stage 1 — the benchmark (1 day).**
N17. Five ticket fixtures, `rake harness:bench`. Baseline the built-ins now, before anything else changes, so stages 2 and 3 have something to be measured against. Anthropic: *"Create evaluations BEFORE writing extensive documentation."*

**Stage 2 — the brief and the contracts, with the built-ins still in place (1 week).**
B1 (`PhaseBrief`, `Toolchain`, `PhaseRecord`), B5 (contracts, sentinel, out-file fallback, failed-run capture), B6 (`executed` → draft PR), N10 (`TestGuard`). Extend the *built-in* prompts to read the brief and emit the contracts. This is the highest-value stage and it is harness-independent: it fixes the specification leak, the silent green PR and reward-hacking on tests without shipping a single SKILL.md. Re-run the benchmark. **If stage 2 alone closes most of the gap, stages 3 and 4 need a much stronger case.**

**Stage 3 — the harness, opt-in (1–2 weeks).**
B2 (bundled harness, Dockerfile COPY, `source_for`, `fw` migration), B3 (prompt shape, drop the change_ref gate), N14 (roster), N16 (wizard). Ship all six skills but map only **investigation, planning and review** to Sammath by default; leave implementation, testing and deployment on the improved built-ins. Those three are where the harness adds capability the built-ins structurally lack: intent discipline and grounded fan-out, a frozen machine-checkable contract, and adversarial verification with per-category precision. Implementation and testing are already well served, and deployment is off by default. Re-run the benchmark with review isolated.

**Stage 4 — promotion and the remaining hazards (as evidence allows).**
N11 (the capped backward edge — only once review's precision table shows the phase is worth acting on), the remaining three phase mappings, per-ticket `git worktree`, the `autonomy: "plan"` gate, and the runner-image question (fatter image or devcontainer exec) for repos whose toolchain the container cannot execute. Promote Sammath from opt-in to default only when the benchmark says so, per phase, not as a block.