# Writing criteria a test can assert

A criterion is a sentence that a later phase can turn into a passing or failing
check without asking you what you meant.

## The test

Read the criterion and try to name the assertion. If you can write
`assert X == Y` or "call this, expect that", it is a criterion. If the honest
answer is "well, it depends what we mean by…", it is a wish.

## Shapes that work

**Behavioural, with the trigger and the outcome:**

> Given a retry sequence that has used all 3 attempts, the next call returns
> 429 and no fourth attempt is enqueued.

**A state change, with the before and the after:**

> After the migration runs, every `orders` row has a non-null `venue_id`, and
> the column is `NOT NULL`.

**An absence, which is checkable:**

> No code path calls `Instrument.fetch` more than once per `(symbol, venue)`
> within a single backtest run.

**A boundary, with the actual number:**

> A payload of exactly 1 MiB is accepted; 1 MiB + 1 byte returns 413.

## Shapes that do not work

| Not a criterion | Why | Fix |
|---|---|---|
| "Performance is improved" | No number, no baseline | "p95 of `/orders` under 200 ms with the existing 10k-row fixture" |
| "The code is clean" | Taste, not behaviour | Drop it; that is review's job |
| "Handles errors gracefully" | Which errors, and what is graceful | "A timeout returns 504 and logs the upstream host" |
| "Tests pass" | Circular — tests pass because you wrote them | Say what the test asserts |
| "Works on mobile" | No device, no viewport, no behaviour | "At 375 px the filter row wraps to two lines and no control is cut off" |

"Tests pass" deserves its own warning: it is the criterion that always
succeeds. It is satisfied by a test that asserts nothing, and it is satisfied by
deleting the test that failed. Later phases treat it as zero evidence.

## Quote the ticket

If `## Intent` says "EU and UK customers", the criterion says "EU and UK
customers" — not "European customers", which is a different set and a real bug.
The same goes for every threshold, status code, field name and enum value.

## Two to six

Fewer than two and the ticket is under-specified. More than six and either the
ticket is two tickets, or you are describing the implementation rather than the
goal — the steps carry that, and repeating it as criteria means review checks
the plan against itself.

---

# The bugfix plan

When `## Findings` carries a root cause, the plan has exactly three tasks:

### 1. Write the failing regression test

Name the file. State what it asserts and what it currently does — it must fail,
and it must fail *for the reason in the root cause*, not because the fixture is
missing.

**Do not fix the bug in this task.** A test written after the fix is a test of
the fix. A test written before it is a test of the bug, and only the second one
would have caught the regression in the first place.

### 2. Implement the fix

The narrowest change that makes that test pass, at the root cause and not at
the symptom. If the root cause is expensive to fix and you are proposing a
symptom-level patch instead, say that explicitly — it is a legitimate call and
a terrible thing to leave implicit.

### 3. Re-run the neighbouring tests

Name them: the other tests in that file, and the tests of the direct callers
you found in `## Findings`. This is the step that catches a fix that broke
something adjacent.

These become three separate commits, in this order. Review and testing check
the ordering from `git log`, so it is verifiable rather than merely promised.
