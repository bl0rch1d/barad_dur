# Refuting a finding

The verifier's job is **not** to check whether a finding is plausible. It is to
try to prove it wrong, and to say REFUTED when it cannot be certain.

That asymmetry is deliberate. A false finding costs a rework round and teaches
the pipeline to distrust its own reviews; a missed Medium costs one comment on
a pull request. Default to REFUTED.

## The six routes

A finding dies if any one of these holds. Each requires evidence — a command
you ran and its output, not a recollection.

### 1. It pre-exists and the change does not make it worse

`git -C <repo> log -L <start>,<end>:<file>` or `git blame` on the lines. If the
defective code predates `base_sha` and the change neither touches it nor
increases how often it is reached, it is not this ticket's finding.

**Except** when the change materially increases exposure — a pre-existing
injection on a path that was internal and is now public is this ticket's
problem. Say which case you found.

### 2. Three or more places do this deliberately

Grep for the pattern. If three or more places in comparable code do the same
thing, it is a convention, not a defect. **Show them** — paths and line
numbers, not a count you assert.

Two is not enough. Two is a coincidence.

### 3. The stated failure cannot occur

Trace the actual path. The finding says "if `x` is nil this raises" — is `x`
ever nil there? Follow every caller. If a guard upstream, a type constraint or a
database `NOT NULL` makes the input impossible, the finding is refuted and the
trace is the evidence.

A finding refuted this way is worth a *calibration note*: the reviewer read the
code correctly and the system correctly makes it unreachable.

### 4. The fix is different, not better

The finding proposes an alternative. Is the alternative actually superior, or
merely different? If the current form is defensible — it works, it matches the
neighbours, it has no stated consequence — the finding is a preference dressed
as a defect. REFUTED.

### 5. It rests on something that does not exist

Grep for the file, method, constant or configuration key the finding names. If
it is not there, the finding is refuted **outright**.

Say so plainly and prominently. A fabricated reference is not one bad finding;
it is a signal about the whole category that reviewer produced, and the report
should treat every other finding from that unit with more suspicion.

### 6. Already refuted, and the code has not changed

Read `refuted.json` from prior rounds. If this finding was killed with evidence
and the lines it concerns are untouched since, it is refuted again. Cite the
round.

## When it stands

STANDS is not the end of your work. **Correct every wrong detail** before it
goes into the report:

- **Mechanism** — does it fail for the reason claimed, or for a different one?
- **Blast radius** — one call site, or every caller?
- **Affected population** — all users, or only those with a flag set?
- **Implied severity** — does the corrected mechanism still justify the tier?

A finding that survives with the wrong mechanism attached is **worse than one
that gets dropped**, because someone will confidently fix the wrong thing and
the real defect will still be there, now with a test asserting the wrong
behaviour.

## Tie-breaker

When two verifiers disagree, a third reads the source **in full** — not the
diff, not the summaries — and rules for one side.

Averaging is not available. "Partially valid, downgrade to Medium" is how a
real Critical becomes a comment nobody reads.

The tie-breaker must also explain what the losing side's evidence actually
showed. It was not nothing, or there would have been no disagreement.
