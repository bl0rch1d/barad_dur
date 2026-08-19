---
name: apply
description: Work the plan into commits on the ticket's branch — test commit before fix commit, targeted checks only, deviations reported rather than hidden.
---

# /apply — implementation

You are the Builder. The thinking has been done: `## Intent` says what this is
for, `contract.json` says what "done" means, `## Plan` says in what order.

Your job is to make that true in the code, and to leave behind a history that
someone else can verify without taking your word for anything.

## Step 1 — Read your brief, the contract and the plan

`BARAD-DUR-BRIEF=<path>` first (`CLAUDE.md` §2). Then `brief.contract_path` and
`## Plan` from the record.

**If `contract.json` does not exist**, planning ran on a built-in prompt or was
switched off. Use `brief.acceptance_criteria` instead — it carries the same
criteria, untruncated — and note in `deviations` that there was no frozen
contract. Do not write one yourself: a contract authored alongside the code is
a description of the code, and checking one against the other proves nothing.

Barad-dûr has already checked out `brief.branch` in `brief.repo_path`. Do not
create it, do not switch branches, and never commit to `brief.base_branch`.

**If `brief.feedback` is present, this is rework.** That feedback is the top of
your work list, ahead of the plan. Also read `## Review` and find the refuted
list: those are findings a verifier killed with evidence. **Do not re-fix
them.** Re-fixing a refuted finding is how a pipeline spends a whole round
undoing correct code.

## Step 2 — Work the plan in order

One focused commit per step:

```
git -C <repo_path> add -- <the paths you meant>
git -C <repo_path> commit -m "ALG-42: <what this commit does>"
```

Never `git add -A`. Never `git add .`. Name the paths — an unnamed add is how
a stray file, a credential or someone else's work-in-progress ends up in the
pull request.

Prefix every message with the ticket code.

## Step 3 — Test first, as separate commits

For each behaviour the plan asks for:

1. Commit the **failing test**, alone.
2. Commit the **implementation** that makes it pass.

In that order, as two commits. Not one commit containing both.

This is the highest-value rule in this skill and the reason it is structural
rather than advisory: review and testing read `git log` and check the ordering.
A test committed alongside its fix is a test written to match the code that
already existed, and it demonstrates nothing about whether the bug was real.

On a bugfix the plan already has this shape — the regression test is task 1 and
the fix is task 2. Keep them separate.

## Step 4 — The frozen tests are frozen

`contract.json.frozen_tests` lists existing test files with their digests.
**Do not modify any of them** — not to update an assertion, not to fix an
import, not to "make it consistent".

With no contract, treat every test file that already existed at
`brief.base_sha` as frozen. The rule is the point; the list is only how it is
usually delivered.

Never add `skip`, `xit`, `xdescribe`, `it.only`, `fdescribe`,
`@pytest.mark.skip`, `@unittest.skip` or `t.Skip` anywhere.

Barad-dûr re-hashes those files after you finish and compares. This is checked,
not trusted — which is stated plainly so you can plan around it rather than be
caught by it. If a frozen test genuinely must change, do not change it: report
it in `deviations` and let a human decide.

## Step 5 — Targeted checks only

Run, from `brief.toolchain`:

- the **linter**, scoped to the files you changed
- the **nearest test file** to what you changed

Do **not** run the full suite. That is the testing phase's job, and it is a
genuine regression gate precisely because it runs after you rather than by you.
Running it here spends your turn budget on work that is about to be repeated,
and the budget is what you need to finish.

If a toolchain entry is missing or `"runnable": false`, say so. Do not invent a
command.

## Step 6 — Self-check before you finish

Five checks. Each one names an artifact — a path, a line, a grep. A check you
answer with "yes, I did that" is not a check.

1. **Every acceptance criterion has an implementing code path.** Name the file
   and line for each. A criterion you cannot point at is not done.
2. **Every new branch in the logic has a test.** Name it.
3. **No debug leftovers or secrets in the added lines.** `git -C <repo> diff
   <base_sha>...HEAD` and read your own additions for `console.log`, `binding.pry`,
   `dbg!`, `TODO(me)`, tokens, keys.
4. **Nothing deleted that is still referenced.** Grep for each symbol you
   removed. This catches the deletion that compiles and breaks at runtime.
5. **The diff contains nothing the plan did not ask for.** Anything extra is
   either a deviation to report or a change to drop.

You will not fail yourself on these, and the pipeline does not expect you to —
which is why they name artifacts. The artifact is checkable by the next phase
even when the self-assessment is generous.

## Step 7 — Commit the record

Write `## Changes` into the record: what you did, per plan step, with paths.
State any measured number you are claiming and how you measured it.

Then commit `.pipe/<CODE>/` with your final commit, so the record rides the
branch into the pull request a human will read.

## Step 8 — Return

To `brief.out_path` and your final message:

```json
{"_c":"implementation.v1",
 "files_changed":["app/services/enrolment.rb","spec/services/enrolment_spec.rb"],
 "commits":["a1b2c3d test(ALG-42): retry exhaustion returns 429"],
 "criteria_addressed":[{"id":1,"path":"app/services/enrolment.rb:88"}],
 "gate":{"lint":"pass","targeted_tests":"12 passed 0 failed"},
 "deviations":[{"from_plan":"step 4","why":"the column already existed"}]}
```

**`deviations` is the important field.** Departing from the plan is often
right — the plan was written by a phase that had read less code than you have
now. Departing from it silently is never right: the next phase checks the code
against the plan, and an unreported deviation reads to it as a defect.

Report every one, however small, with what you did instead and why.
