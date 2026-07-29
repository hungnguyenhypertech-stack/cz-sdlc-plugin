# RD Guide — Sizing and Splitting

An RD (Requirement Detail) is the atomic unit of work in CZ-Harness: the smallest thing that
can be claimed, tested, and gated independently. This guide defines when an RD is valid, what
automatically triggers a split, who is allowed to commit a split, and walks through worked
examples on a realistic scenario so the rules aren't abstract.

## The Six-Point Validity Test

An RD is valid **only if all six of the following hold.** If any one fails, the RD must be
split before it can be accepted into the registry.

1. **Exactly one observable behavior.** You can describe what the RD does in one sentence with
   no "and" hiding a second thing.
2. **1–3 acceptance criteria.** Zero AC means the RD isn't testable yet (not ready). More than
   3 AC is almost always a sign two behaviors got merged into one RD.
3. **Independently testable on its own.** The RD's test suite must be able to run and mean
   something without any other RD's code existing yet, even if it needs a stub/mock for a
   dependency.
4. **Estimate bounds.** `estimate.expected_h <= 4` **and** `estimate.pessimistic <= 6`. Both
   must hold — an RD with a low expected but a blown-out pessimistic tail is hiding
   uncertainty that should be split out (usually into a spike).
5. **Exactly one module.** The RD must map to exactly one entry in MODULEMAP. If satisfying
   the AC requires touching two modules, that's a signal the behavior spans a boundary that
   should be two RDs (or the module boundary itself is wrong — escalate, don't force it).
6. **No conjunction hiding a second behavior.** Words like "and," "also," "then also" in the
   RD *statement* (not the AC) are a red flag. Detail belongs in the acceptance criteria, not
   stacked into the statement as a second requirement.

## Automatic Split Triggers

An agent (typically ba or sa during drafting, or test-designer discovering it mid-loop) must
propose a split when any of the following occurs:

- More than 3 acceptance criteria drafted for one RD.
- An AC spans two modules (e.g., one AC asserts on ETL validation logic, another asserts on
  dashboard rendering).
- A conjunction is found in the statement text.
- `estimate.expected_h > 4` or `estimate.pessimistic > 6`.
- An agent exhausts its context window mid-loop while working the RD — this is treated as
  empirical evidence the RD was too large, regardless of what the estimate said going in.

**Splitting is proposed by agents, committed only by a human.** An agent that detects a split
trigger writes a split proposal (new RD ids, redistributed AC, updated estimates) into the
registry as a *pending* change; no agent may finalize it. A human must review the proposal and
either commit it (the original RD id becomes `state:withdrawn`, new RD ids become active) or
reject it and instruct the agent to proceed differently.

## Worked Examples — Nightly Refresh / Source Reconciliation Dashboard

Scenario: a dashboard that nightly-refreshes reconciliation data from multiple upstream
branch sources, validates incoming rows through an ETL layer, and surfaces refresh status and
data quality to an operations user.

### Example A — GOOD (no split needed)

```yaml
id: RD-PB04-042.01
module: etl-ingest
statement: >
  When the nightly refresh job pulls data from a branch source, rows that fail ETL
  schema validation are rejected and logged rather than inserted into the reconciliation table.
ac:
  - id: AC-PB04-042.01-1
    given: a branch source file containing 3 valid rows and 2 rows missing a required
           account_id field
    when: the nightly refresh job processes the file
    then: the 3 valid rows are inserted into the reconciliation table and the 2 invalid
          rows are written to the rejected_rows log with a validation_error reason code
  - id: AC-PB04-042.01-2
    given: a branch source file where every row fails validation
    when: the nightly refresh job processes the file
    then: zero rows are inserted, the refresh_run record for that source is marked
          partial_failure, and the rejected_rows log contains one entry per row
estimate:
  optimistic: 1.5
  likely: 2.875
  pessimistic: 5
  expected_h: 3        # (optimistic + 4*likely + pessimistic) / 6, per rd-template.yaml
```

**Why this passes all six:** one observable behavior (malformed-row rejection during nightly
ETL); 2 AC, both about the same behavior from different input shapes; testable in isolation
with a fixture branch-source file, no dependency on dashboard rendering; expected 3h /
pessimistic 5h, both within bounds; maps to exactly one module (`etl-ingest`); no conjunction
in the statement — the AC carry the two scenarios, the statement stays singular.

### Example B — Needed Splitting

Original draft, as first written by the ba agent:

```yaml
id: RD-PB04-042.05   # DRAFT — never committed as-is
module: etl-ingest / dashboard-ui   # <- already a red flag
statement: >
  When a branch source connection fails during the nightly refresh, the system retries
  up to 3 times with backoff, and also surfaces a "source degraded" banner on the
  dashboard so operations users know the data may be stale.
ac:
  - given: a branch source that fails to connect on first attempt
    when: nightly refresh runs
    then: the job retries with exponential backoff (1s, 2s, 4s) up to 3 attempts
  - given: a branch source that fails all 3 retry attempts
    when: the retry budget is exhausted
    then: the refresh_run record for that source is marked failed and an alert event
          is emitted
  - given: a refresh_run record marked failed or partial_failure for a source
    when: an operations user loads the dashboard
    then: a "source degraded" banner appears naming the affected source and the
          timestamp of the last successful refresh
  - given: the degraded source recovers on a later nightly run
    when: the dashboard is reloaded
    then: the banner disappears
estimate:
  optimistic: 3
  likely: 5.75
  pessimistic: 10
  expected_h: 6        # (optimistic + 4*likely + pessimistic) / 6 — already over the
                       # 4h bound on its own, which is exactly the fourth trigger below
```

**Why this fails the test — three separate triggers fired:**

- **4 acceptance criteria** (trigger: >3 AC).
- **Two modules** — the first two AC are `etl-ingest` retry/backoff behavior; the last two AC
  are `dashboard-ui` rendering behavior (trigger: AC spans two modules).
- **Conjunction in the statement** — "retries... **and also** surfaces a banner" is exactly
  the pattern the sixth validity check is looking for (trigger: conjunction hiding a second
  behavior).
- **Estimate out of bounds** — expected_h 6 > 4, pessimistic 10 > 6 (trigger: estimate
  bounds), which is itself downstream of the RD actually containing two behaviors.

**The proposed split**, written by the agent as a pending change for human commit:

```yaml
# Split 1 — retry/backoff behavior stays in etl-ingest
id: RD-PB04-042.05
module: etl-ingest
statement: >
  When a branch source connection fails during the nightly refresh, the system retries
  up to 3 times with exponential backoff before marking the source failed.
ac:
  - given: a branch source that fails to connect on first attempt
    when: nightly refresh runs
    then: the job retries with exponential backoff (1s, 2s, 4s) up to 3 attempts
  - given: a branch source that fails all 3 retry attempts
    when: the retry budget is exhausted
    then: the refresh_run record for that source is marked failed and an alert event
          is emitted
estimate: { optimistic: 1.5, likely: 2.875, pessimistic: 5, expected_h: 3 }

---
# Split 2 — banner behavior moves to dashboard-ui, depends on Split 1's refresh_run field
id: RD-PB04-042.06
module: dashboard-ui
statement: >
  When a refresh_run is marked failed or partial_failure, the dashboard surfaces a
  "source degraded" banner naming the source and its last successful refresh time.
ac:
  - given: a refresh_run record marked failed or partial_failure for a source
    when: an operations user loads the dashboard
    then: a "source degraded" banner appears naming the affected source and the
          timestamp of the last successful refresh
  - given: the degraded source recovers on a later nightly run
    when: the dashboard is reloaded
    then: the banner disappears
estimate: { optimistic: 1.5, likely: 2.875, pessimistic: 5, expected_h: 3 }
```

Each half now independently passes all six checks. `RD-PB04-042.05` (original id) is reused
for the retry/backoff half since it's the larger conceptual continuation; `.06` is a newly
minted id for the banner half. The original combined draft is never committed to the registry
at all in this case since it was caught pre-commit — had it already been accepted and then
split later, the original id would move to `state:withdrawn` rather than being deleted (see
`TRACEABILITY.md` on id immutability).
