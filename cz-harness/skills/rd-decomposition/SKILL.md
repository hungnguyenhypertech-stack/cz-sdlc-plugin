---
name: rd-decomposition
description: Size and split Requirement Details (RDs) for cz-harness. Invoke when a WBS leaf needs decomposing into one or more RDs, when an existing RD looks too big or vague to claim/test/gate independently, or when a test-designer/dev agent mid-loop suspects an RD is hiding a second behavior (context exhaustion, thrash, an AC that spans two modules). Use this to check an RD statement plus its acceptance criteria against the six-point validity test and to propose a concrete split when it fails.
---

# RD Decomposition

An RD (Requirement Detail) is the atomic unit of work in cz-harness: the smallest thing that
can be claimed, tested, and gated independently. This skill packages the sizing/splitting
rules from `docs/RD-GUIDE.md` and `commands/cz-rd.md` (Phase 4→RD decomposition, `/cz:rd`) so
they can be applied directly to any RD draft, without re-reading those files.

## When to use this skill

- A `/cz:rd` invocation is decomposing a current-wave WBS leaf into candidate RDs and needs to
  check each candidate against the validity rules before it can be committed.
- A human or agent is staring at an existing RD that "feels big" and needs a structured
  yes/no test rather than a gut call.
- `test-designer` or `dev` hits a split trigger mid-loop (context exhaustion, thrash, an AC
  that turns out to need two modules) and must write a split proposal rather than silently
  push through.

## The Six-Point Validity Test

An RD is valid **only if all six hold.** Check every one, every time — if any one fails, the
RD must be split before it can be accepted into the registry.

1. **Exactly one observable behavior.** You can describe what the RD does in one sentence with
   no "and" hiding a second thing.
2. **1–3 acceptance criteria.** Zero AC means the RD isn't testable yet (not ready). More than
   3 AC is almost always a sign two behaviors got merged into one RD.
3. **Independently testable on its own.** A TC could be written today with no missing
   fixture/data — the RD's test suite must run and mean something without any other RD's code
   existing yet, even if it needs a stub/mock for a dependency.
4. **Estimate bounds.** `estimate.expected_h <= 4` **and** `estimate.pessimistic_h <= 6`. Both
   must hold — a low expected with a blown-out pessimistic tail is hiding uncertainty that
   should be split out (usually into a spike).
5. **Exactly one module.** The RD must map to exactly one entry in MODULEMAP. If satisfying the
   AC requires touching two modules, that's a signal the behavior spans a boundary that should
   be two RDs (or the module boundary itself is wrong — escalate, don't force it).
6. **No conjunction hiding a second behavior.** Words like "and," "also," "then also" in the RD
   *statement* (not the AC) are a red flag. Detail belongs in the acceptance criteria, not
   stacked into the statement as a second requirement.

## Complexity Heuristic → RD-Level Profile Override

At the same drafting moment the six-point test runs, `ba`/`planner` also decide whether this RD
qualifies for a `profile:` override (`rd-template.yaml`'s `profile:` field) — a downgrade of
*this RD's own* ceremony depth below whatever the module/project profile would otherwise impose.
This is not a new gate or a new document type; it reuses the existing `light|standard|heavy`
profile mechanism (`docs/LIGHTWEIGHT-MODE.md`, `config/gates.yaml`'s gate-profile matrix), just
applied at RD grain instead of only at project/module grain.

An RD is **light-eligible** when all of:

- `layer: 1` (surface, not foundation)
- `estimate.expected_h <= 1.5` (well inside the six-point test's own `<= 4` ceiling — this is a
  tighter bar, not the same one)
- Exactly 1 AC drafted

When eligible, set `profile: light` on the RD. This can only ever *lower* ceremony relative to
the module/project profile — never raise it (an RD under a `light` module cannot declare
`profile: heavy` to get more scrutiny than the project asked for is fine, since that direction
is not restricted, but the reverse — a `standard`/`heavy` module RD declaring `profile: light` to
dodge review — is exactly what this heuristic exists to make principled rather than arbitrary; a
hazard RD is never eligible regardless of these signals, `hazard: true` always wins). Omit the
field entirely when not eligible; absence means "inherit the module/project profile" and is the
common case.

## Automatic Split Triggers

Propose a split (typically as `ba`/`sa` during drafting, or `test-designer`/`dev` discovering
it mid-loop) whenever any of the following fires:

- More than 3 acceptance criteria drafted for one RD.
- An AC spans two modules (e.g., one AC asserts on ETL validation logic, another asserts on
  dashboard rendering).
- A conjunction is found in the statement text.
- `estimate.expected_h > 4` or `estimate.pessimistic_h > 6`.
- An agent exhausts its context window mid-loop while working the RD — treated as empirical
  evidence the RD was too large, regardless of what the estimate said going in (a
  stall/thrash signal visible in `telemetry/events.jsonl`).

## Fan-Out and Depth Cap

Splitting has no natural stopping point on its own — a WBS leaf that keeps triggering splits can
fragment indefinitely, which trades "RD too big" for "ceremony overhead now outweighs the code."
Each split product records `split_from` (the parent RD id) and `split_depth` (parent's
`split_depth + 1`, starting at 0 for a non-split RD) in its `rd-template.yaml` fields.

For any WBS leaf whose *originating* RD was `profile: light`-eligible under the heuristic above
(i.e. the underlying work was assessed as small to begin with):

- **Fan-out cap: 4 siblings per split.** A single split proposal may not produce more than 4
  child RDs.
- **Depth cap: 2.** A split product (`split_depth: 1`) may itself be split once more
  (`split_depth: 2`), but a `split_depth: 2` RD triggering yet another split does not auto-propose
  a further split.

WBS leaves that were *not* light-eligible (genuinely larger/more complex scope) are not subject to
this cap — the existing uncapped six-point-test behavior applies, but each additional split beyond
depth 2 must state in its split proposal's rationale why the extra split was necessary, so a human
reviewing `human_gates.rd_commit` can see the fragmentation was deliberate, not accumulated.

**When a cap would be exceeded:** do not auto-propose another split. Instead, flag it as a
module/WBS-boundary problem for human re-scoping — the signal at that point is that decomposition
alone isn't fixing the sizing problem, the WBS leaf or module boundary itself is miscut. Write
this as a note in the pending split proposal rather than silently forcing a 5th sibling or a 3rd
level of depth.

**Splitting is proposed by agents, committed only by a human.** An agent that detects a split
trigger writes a split proposal (new RD ids, redistributed AC, updated estimates) into the
registry as a *pending* change; no agent may finalize it. A human reviews the proposal and
either commits it (the original RD id becomes `state:withdrawn`, new RD ids become active) or
rejects it and sends the agent back to draft differently. This is gated by
`human_gates.rd_commit` in `config/gates.yaml`, which defaults `true` — the one `human_gates`
key that defaults **on** (plan §4.1: "Splitting is proposed by agents and committed by the
human. An agent that can silently redefine the work has escaped the delegation map."). Any of
the six rules failing sends the draft back automatically, regardless of that setting.

## Worked example — good vs. needs-splitting

Scenario: a dashboard that nightly-refreshes reconciliation data from multiple upstream branch
sources, validates incoming rows through an ETL layer, and surfaces refresh status and data
quality to an operations user.

**GOOD — passes all six, no split needed:**

```yaml
id: RD-PB04-042.01
module: etl-ingest
statement: >
  When the nightly refresh job pulls data from a branch source, rows that fail ETL
  schema validation are rejected and logged rather than inserted into the reconciliation table.
ac:
  - id: AC-PB04-042.01-1
    given: a branch source file containing 3 valid rows and 2 rows missing a required account_id field
    when: the nightly refresh job processes the file
    then: the 3 valid rows are inserted and the 2 invalid rows are written to rejected_rows with a validation_error reason code
  - id: AC-PB04-042.01-2
    given: a branch source file where every row fails validation
    when: the nightly refresh job processes the file
    then: zero rows are inserted, refresh_run is marked partial_failure, rejected_rows has one entry per row
estimate: { optimistic: 1.5, likely: 2.875, pessimistic: 5, expected_h: 3 }
```

One observable behavior (malformed-row rejection); 2 AC about the same behavior from
different input shapes; testable in isolation with a fixture file; expected 3h / pessimistic
5h, both in bounds; exactly one module (`etl-ingest`); no conjunction in the statement.

**NEEDS SPLITTING — three triggers fire at once:**

```yaml
id: RD-PB04-042.05   # DRAFT — never committed as-is
module: etl-ingest / dashboard-ui   # already a red flag
statement: >
  When a branch source connection fails during the nightly refresh, the system retries
  up to 3 times with backoff, and also surfaces a "source degraded" banner on the
  dashboard so operations users know the data may be stale.
# 4 AC drafted (>3 → trigger), 2 in etl-ingest + 2 in dashboard-ui (spans modules → trigger),
# "retries... and also surfaces a banner" (conjunction → trigger)
estimate: { optimistic: 3, likely: 5.75, pessimistic: 10, expected_h: 6 }  # expected_h 6 > 4, pessimistic 10 > 6 (estimate bounds → trigger)
```

The proposed split, written as a pending change for human commit:

```yaml
# Split 1 — retry/backoff stays in etl-ingest, id reused (larger conceptual continuation)
id: RD-PB04-042.05
module: etl-ingest
statement: >
  When a branch source connection fails during the nightly refresh, the system retries
  up to 3 times with exponential backoff before marking the source failed.
ac: [ 2 AC — connect-fails-once-retries, retries-exhausted-marks-failed ]
estimate: { optimistic: 1.5, likely: 2.875, pessimistic: 5, expected_h: 3 }

---
# Split 2 — banner behavior moves to dashboard-ui, depends on Split 1's refresh_run field, new id minted
id: RD-PB04-042.06
module: dashboard-ui
statement: >
  When a refresh_run is marked failed or partial_failure, the dashboard surfaces a
  "source degraded" banner naming the source and its last successful refresh time.
ac: [ 2 AC — banner-appears-on-failure, banner-disappears-on-recovery ]
estimate: { optimistic: 1.5, likely: 2.875, pessimistic: 5, expected_h: 3 }
```

Each half now independently passes all six checks. If the combined draft had already been
accepted before the split was caught, the original id would move to `state:withdrawn` rather
than being deleted — ids are immutable and never reused (see the `traceability` skill).

## The `/cz:rd` 7-beat loop (how this check gets applied in practice)

1. **Context** — load the WBS leaf, its parent module (MODULEMAP), and ARCH for interface detail.
2. **Plan** — draft candidate RD(s), each with a short `summary` line (~90 chars) for the board's RD table.
3. **Delegate** — send drafts to the phase owner (`planner` for first-pass, or `test-designer`/`dev` if a split surfaces mid-`/cz:build`). Any agent may *propose* a split.
4. **Execute** — run the six-point test; auto-propose a split on any trigger above. Each split becomes `<nnn>.01`, `<nnn>.02`, ... under the same parent WBS leaf.
5. **Gate** — `human_gates.rd_commit` (default `true`) decides whether a human must commit each RD/split. If a project sets it `false` for unattended runs, the six rules are still re-checked programmatically, and `human_gates_bypassed: true` plus an `rd_auto_committed` governance event are written so the bypass is loud, not silent.
6. **Log** — append a Delivery Log entry to `deliverables/understanding-log/rd-commits.md`.
7. **Iterate** — repeat until every current-wave WBS leaf has ≥1 committed, valid RD.

Exit condition: every current-wave WBS leaf has at least one committed, six-rule-valid RD, each then ready for `/cz:dor`.
