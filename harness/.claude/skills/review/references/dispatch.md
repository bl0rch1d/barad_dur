# Cutting a diff into review units

The default instinct is one unit per file. It is the wrong default: it produces
reviewers who each see a fragment, and it is *structurally incapable* of finding
the most common real defect in a repeated change — the call site that should
have been updated and was not, which is by definition not in the diff.

## The three groupings that beat per-file

### 1. A source file and its test are one unit

Split apart, the source reviewer cannot tell whether the test covers the change
and the test reviewer cannot tell whether the assertion is meaningful. Together,
one agent can answer both.

### 2. The same change repeated across files is one consistency unit

If a rename, a new argument, a changed call convention or a new guard appears in
several files, that is one unit, and its most valuable output is **the place
that did not get it**.

Instruct that unit explicitly:

> Grep the whole repository — not only the diff — for the old form. Every
> remaining occurrence is either a deliberate exception (say why you believe
> that) or a missed call site (a finding). The missed one is not in your diff;
> you will only find it by looking outside it.

### 3. A criteria-conformance unit, always

One agent per run whose only job is: for each criterion in `contract.json`, find
the code path that implements it, by grepping the repository independently.

Its standing instruction:

> "The tests pass" is **zero evidence** that a criterion is satisfied. A test
> can assert nothing, can assert the wrong thing, and can have been written to
> match the code. Find the implementing line. If you cannot, the criterion is
> `not_satisfied`, whatever the suite says.

## Prompt template for a `review-unit`

Every unit prompt carries all five of these. Compressing them is how a reviewer
ends up with the wrong premise.

```
INTENT (verbatim from the record — do not re-derive it from the code):
<paste ## Intent>

CONTRACT: <path to contract.json>   RECORD: <path to record.md>
Read them yourself if you need more than I have pasted.

BASE: <base_sha>    DIFF DEFINITION: <base>...HEAD
REPO: <repo_path>   — every git command needs -C <repo_path>

YOUR UNIT: <files, or the consistency instruction, or the criteria list>

WHAT I NEED BACK: findings only. Each with file:line, what is wrong, why it
matters in terms of the intent above, and the evidence you have. If you are not
sure, say so and say what would settle it — an uncertain finding labelled as
uncertain is useful; an uncertain finding stated confidently is not.

DO NOT fix anything. DO NOT edit any file. Report.
```

## Caps, and saying so

| Files changed | Units |
|---|---|
| ≤ 3 | none — do it inline |
| 4–15 | ≤ 3 |
| > 15 | ≤ 5, grouped by directory |

Above five units, coverage is partial. That is an acceptable trade and an
unacceptable secret. Write in the report, by name, which directories or files
no unit reached.

Emit every `Agent` call in a single message. Whether they actually run in
parallel is the runtime's decision, not yours — if they serialize, note it as a
method deviation and carry on. Do not respond to serialization by cutting units.
