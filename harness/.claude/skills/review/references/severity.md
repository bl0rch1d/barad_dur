# Severity

Severity decides what happens next: Critical and High map to `blocking` and
send the whole ticket back for rework. Medium and Polish go into the report.
Getting this wrong in either direction is expensive — an inflated High costs a
whole rework round, and a deflated Critical ships.

**Every anchor below is conditional on a precondition you must detect in this
repository.** An anchor whose precondition is absent is not a softer anchor; it
does not exist this run. State in the report which anchors were in force.

## Critical

Ship-stopping. The change is wrong in a way that damages something.

1. **Data loss or corruption** on a path the change introduces or alters —
   a migration without a reverse, a write that can partially apply, a delete
   whose scope is wider than the criterion.
   *Precondition: the change touches persistence.*
2. **An authentication or authorization boundary moves** — a check removed,
   weakened, or bypassable by a route the change adds.
   *Precondition: the repository has an auth layer the change touches.*
3. **A secret, token or credential** appears in tracked content, in a log line,
   or in an error message the change adds.
   *Precondition: none. This one is universal.*
4. **Money is computed differently** and no criterion asked for it — rounding,
   currency, tax, fee, or ordering of operations on a monetary value.
   *Precondition: the repository handles monetary amounts.*

## High

Not ship-stopping, but a real defect that will be hit.

**Universal — these hold in any repository:**

5. **A public function's new error path has no caller that handles it.** Grep
   the callers. If the new raise, reject or error return is unhandled at every
   call site, the change moves a failure from one place to a worse one.
6. **A serialization format changed with no version guard** — a stored, cached
   or transmitted shape altered such that data written by the old code cannot be
   read by the new, or the reverse.
7. **A new dependency with no lockfile entry**, or a lockfile entry with no
   manifest change. Either direction means the build is not reproducible.

**Conditional — check the precondition first:**

8. **A criterion has no implementing code path.** *Precondition: a contract
   exists — it always does here.*
9. **A test was weakened, skipped or deleted.** *Precondition: none.*
10. **Hardcoded user-facing copy** where the project routes copy through an i18n
    layer. *Precondition: an i18n layer exists and is used by neighbours.*
11. **A new environment variable absent from the example env file.**
    *Precondition: the repo has an example env file.*
12. **Generated output that fails its own generator's validator.**
    *Precondition: the repo has codegen with a validator.*
13. **A new column absent from the change-notification path.**
    *Precondition: the repo has such a path.*

Anchors 10–13 are dead in a repository without i18n, without an example env
file, without codegen. Do not stretch them to fit; that collapses High into
Medium and the tier stops meaning anything.

## Medium

Real, worth fixing, not worth a rework round on its own. Missing edge-case
handling that is unlikely rather than impossible; a test that asserts less than
it appears to; an inefficiency with a bounded cost; a deviation from the plan
that was not reported.

## Polish

Naming, formatting, comment accuracy, ordering. **Never individually verified** —
label it that way in the report every time, and never let Polish enter a
precision calculation.

## Convention findings cap at Medium

Unless the rule is written down in `brief.repo_conventions` or enforced by a
lint config in the repository, a convention finding is at most Medium.

And before raising one at all, **cite the adoption rate of the narrowest
comparable construct**. Not "this codebase uses service objects" — how many of
the *directly comparable* files do the thing you are asking for, out of how
many. Grep it and give the fraction.

If the narrow rate is below half, conforming to the neighbours **is the correct
call and there is no finding.** The change is following the local majority; your
preference is not the repository's convention.

## The anti-rationalisation check

Before you record any finding, ask: **am I describing a defect, or am I
describing a different choice?**

The tell is the shape of your own sentence. "This should use X instead of Y" is
a preference. "This uses Y, and Y drops the venue, so two venues collide at
`cache.rb:88`" is a defect — it names a consequence and points at it.

If you cannot name the consequence and point at where it happens, you do not
have a finding. Drop it, or move it to `decisions_needed` where a human can
weigh a trade-off you are not in a position to make.
