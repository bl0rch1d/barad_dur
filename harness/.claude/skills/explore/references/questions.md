# Asking the user something

Every question you ask parks the ticket until a human answers it. That is the
correct trade when the answer changes what gets built, and a waste of the
user's attention otherwise.

Ask only when **both** are true:

1. The answer would change an acceptance criterion, or change a file that will
   be edited.
2. No defensible default exists — meaning you cannot pick one and write down
   why, such that a reasonable reviewer would accept the reasoning.

## Categories that make a question a candidate

These are the ones where guessing wrong is expensive and the cost lands on
someone other than you. A ticket touching one of these is a candidate for a
question — not an automatic question.

| Category | The question is usually about |
|---|---|
| Personal data | what is stored, for how long, who can read it |
| Authentication | who the change lets in, and by what route |
| Authorization | which role gains or loses an ability |
| Money | rounding, currency, who is charged, what happens on partial failure |
| Destructive migrations | whether the old data is kept, and what reverses it |
| Public API shape | whether a caller outside this repo breaks |
| Notifications | who gets contacted, and whether they can have asked not to be |

Outside these, the default is: choose, and record the choice as an assumption
in `## Findings` with what would falsify it.

## Writing a question the user can answer in five seconds

**Ask about the decision, not the implementation.** "Should the cache be keyed
by venue as well as symbol?" is an implementation detail you should decide.
"Should two venues quoting the same symbol be treated as one instrument or
two?" is a product decision only the user has.

**Give two or three concrete options**, each of which you would be willing to
build. Never offer an option you have already decided is wrong; you are asking,
not campaigning.

**Say why it matters in one line** — the consequence of picking each way, not a
restatement of the question.

**Never ask an open question.** There is no text box; the user picks an option.

## Bad and better

> ❌ "How should errors be handled?"
> Too broad, no options, and it is your job.

> ❌ "Should I use Redis or Memcached for the cache?"
> An implementation choice. Pick one, record why.

> ✅ "A retry that exhausts its budget: fail the request, or fall back to the
> stale cached value?"
> *Why: failing is correct but user-visible; stale data is invisible but can be
> wrong for up to an hour.*
> Options: `Fail the request` · `Serve stale`

## Two is the ceiling, zero is the norm

Two questions is the maximum, and most tickets should ask none. If you find
yourself with three, at least one of them is a decision you should be making.
