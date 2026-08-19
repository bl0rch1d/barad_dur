# Writing `## Intent`

Intent is what the change is *for*. It is not what the change does, and it is
emphatically not what the code ended up doing.

This section is quoted verbatim by planning, review and testing. Every one of
them will believe it. A wrong premise here produces confident, wrong findings
later — in several reviewers at once, all agreeing with each other.

## Where intent comes from, in order

1. **The ticket description.** First and best.
2. **Answered questions** in `brief.answered_questions`. A decision the user
   already made is intent, and it is binding.
3. **Acceptance criteria**, if planning has somehow already run.
4. Nothing else.

## Where it never comes from

**Never from a commit subject.** Subjects compress, and the compression drops
exactly the distinction that matters. "Fix retry handling" tells you nothing
about whether retries should stop or continue on a 429.

**Never from the diff.** A reviewer who infers intent from the change is
grading the change against itself: whatever the code does becomes what it was
supposed to do, and no defect can be found by definition.

**Never from a similar past ticket.** It is evidence about how this team works,
not about what this ticket wants.

## Quote, do not paraphrase

If the ticket enumerates a set, names a threshold, or gives an identifier,
reproduce it **exactly**:

- "retries stop after 3 attempts" — not "retries are limited"
- "for EU and UK customers" — not "for European customers"
- "returns 429" — not "returns an error"

Paraphrase drops the number, and the number is the requirement. Reviewers
downstream will check the code against your words, not against the ticket.

## When the ticket says nothing

Write that. Literally:

> The ticket does not state what this is for. It asks for X to be done. I have
> assumed the purpose is Y, because Z in the existing code. If that is wrong,
> the acceptance criteria below are wrong too.

That is a useful sentence. An invented purpose stated confidently is not — it
becomes the contract, and nobody downstream can tell it was a guess.

## Direction matters

State the change in the direction the ticket states it. "Reduce the timeout to
5s" and "raise the timeout to 5s" have the same endpoint and opposite bugs, and
a reviewer who has the direction backwards will confirm the wrong one.

## Length

Three to six lines. If you need more, the ticket is two tickets, and that
belongs in the plan's `additional_tickets`, not here.
