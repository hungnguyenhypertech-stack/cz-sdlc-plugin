---
name: traceability
description: Reason about cz-harness's ID scheme, content_hash freeze rule, and RTM orphan classes. Invoke when minting or parsing an ID (REQ/RD/AC/TC/WBS/NFR/GATE/HS), when deciding whether a test case is fresh/stale/missing, when explaining what content_hash does and doesn't cover, or when generating/interpreting an RTM and its orphan findings.
---

# Traceability

Every artifact cz-harness produces is addressable by a stable id, and every id participates in
a traceability graph the RTM (Requirements Traceability Matrix) generator walks. This skill
packages `docs/TRACEABILITY.md` and plan §5 so the ID scheme, the freeze rule, and the orphan
classes can be applied directly — computing an ID, judging TC freshness, or interpreting an RTM
— without re-deriving them from source.

## When to use this skill

- Minting a new REQ/RD/AC/TC/WBS/NFR/GATE/HS id, or parsing an existing one to find what it
  traces back to.
- Deciding whether a TC is `fresh`/`stale`/`missing` given an RD's current `content_hash`.
- Explaining why editing an RD's estimate doesn't invalidate its tests, but editing an AC does.
- Generating or reading an RTM (`/cz:report`) and interpreting its orphan findings.

## ID Scheme

| Prefix | Format | Meaning |
|---|---|---|
| `REQ` | `REQ-<proj>-<nnn>` | A top-level requirement, typically stakeholder-facing |
| `RD` | `RD-<proj>-<nnn>.<mm>` | A Requirement Detail — the atomic delivery unit, always a child of one REQ (`nnn` matches the parent REQ, `mm` disambiguates siblings) |
| `AC` | `AC-<proj>-<nnn>.<mm>-<k>` | An acceptance criterion under RD `<nnn>.<mm>`; `k` is the AC's *index* within that RD, not a global ordinal |
| `TC` | `TC-<proj>-<nnn>.<mm>-<k>[N\|P\|F]` | A test case tied to AC index `k` of the same RD. Suffix denotes test *kind*: bare = acceptance (happy path), `N` = negative, `P` = permission/role-based, `F` = NFR-performance. Multiple TCs can share the same `k` with different suffixes |
| `WBS` | `WBS-<proj>-<a>.<b>.<c>` | Work breakdown structure node, independent hierarchy from REQ/RD (planning view, not requirements view) |
| `NFR` | `NFR-<proj>-<nnn>` | A non-functional requirement, referenced by RDs via `nfr_refs`, not owned by any single RD |
| `GATE` | `GATE-<rd-id>-<nn>` | A specific gate decision instance for an RD (`nn` disambiguates retries) |
| `HS` | `HS-<proj>-<nnn>` | A hard-stop record — raised on contradiction, closed only by human action |

**Critical detail on the `TC` suffix**: `k` always refers back to the AC index it validates,
**never** to the test's own creation order. `TC-PB04-042.01-2N` is always the negative-path
test for AC #2 of that RD — you can compute which AC any TC belongs to purely from its id.

**Display short forms** (readability only, never stored/logged): board cards show
`<nnn>.<mm>`; prose uses `RD-<nnn>.<mm>`; diagrams may elide `<proj>` as `TC-…-1`. Short forms
never appear in `rd/*.yaml`, `events.jsonl`, or gate records — those always use fully-qualified
ids.

## Immutability

IDs are permanent. Once minted, an id is **never reused**, even after its artifact leaves
active scope. A descoped RD transitions to `state: withdrawn` — it is never deleted from the
registry. Renumbering is not a supported operation. This matters because:

- Historical telemetry (`telemetry/events.jsonl`) references RD ids, and those events must
  remain resolvable years later for audit purposes.
- A withdrawn RD's id staying reserved prevents a future RD from accidentally reusing an id
  that carries different, stale meaning to anyone who remembers the old one.

## `content_hash` and what it covers

`content_hash` is computed **only** over the fields that define what "correct" means for an
RD: `statement`, `ac[]`, and `nfr_refs`. It explicitly **excludes** `estimate`,
`assigned_agent`, `priority`, and other operational metadata.

Reasoning: editing an estimate or reassigning an agent doesn't change what a passing test looks
like, so it must not invalidate existing test evidence. Editing an AC changes the definition of
correct behavior, so any test derived from the old AC is now testing the wrong thing and must
be flagged.

## The Freeze Rule

Every TC carries an `rd_hash` field — a snapshot of the RD's `content_hash` at the moment the
test was derived. Freshness is a pure comparison:

| TC state | Condition |
|---|---|
| `fresh` | `TC.rd_hash == RD.content_hash` |
| `stale` | `TC.rd_hash != RD.content_hash` (the RD changed since this test was derived) |
| `missing` | An AC exists with no TC at all pointing to it |

**When a normative field changes**, this sequence fires automatically:

1. `RD.content_hash` changes and `RD.version` increments.
2. Every TC linked to that RD flips to `stale` immediately — a pure recomputation, nothing
   re-runs yet.
3. `guard-rd-freeze` blocks any further writes to that RD's source paths until `test-designer`
   re-derives the affected tests and produces a fresh red log against the new AC (see the
   `sdd-loop` skill for the hook mechanics).
4. The RD's state moves `stale` → back to `red` once re-derivation succeeds, and the *prior*
   evidence chain (old gate records, old telemetry) is retained rather than overwritten — the
   history shows both what passed before and what changed.
5. An `rd_changed` event is written to telemetry recording who changed what, which fields
   changed, which TC ids went stale, and which downstream RDs (via `nfr_refs` or dependency
   edges) depend on this RD and may need review.

This is the mechanism that prevents "the test still shows green" from being misleading evidence
after a requirement quietly changed underneath it — and it's exactly the pattern `ai-reviewer`
is required to hunt for as "silent drift."

## RTM Orphan Classes

The RTM generator (`/cz:report`) checks for seven classes of orphan — an artifact that exists
but isn't properly linked into the traceability graph:

1. **REQ with no RD** — a requirement with nothing delivering against it.
2. **RD with no AC** — an RD accepted without acceptance criteria (should be structurally
   impossible post-validity-check; the RTM re-verifies).
3. **AC with no TC** — the `missing` TC state surfaced at the RTM level.
4. **TC with no RD/AC back-reference** — an orphaned test claiming to validate something that
   no longer resolves.
5. **RD with no WBS mapping** — delivery work with no planning-side counterpart.
6. **NFR with no referencing RD** — a non-functional requirement nobody is actually building
   against.
7. **GATE record with no resolvable RD** — a gate decision pointing at an RD id that isn't in
   the current registry (usually a bad withdrawal or an id typo — not a legitimate withdrawn
   RD, since withdrawn RDs remain resolvable).

## Severity by profile

| Profile | Behavior on orphan detection |
|---|---|
| Standard | Blocks the RTM report from generating |
| Heavy | Blocks the RTM report from generating |
| Light | Warns only — the report generates with orphans listed, does not fail the run |

This mirrors Light's general posture: it trades some rigor for speed, but always by explicit,
logged relaxation rather than silent omission.

## Estimation rolls up, not down

`/cz:wbs` produces `WBS-PB0X.md` (rolling-wave depth: task/feature/epic). Each RD names exactly
one WBS leaf; a leaf holds many RDs. Three-point estimates live on the RD; `EST-PB0X.md`
aggregates RD → leaf → wave, which is what makes "estimation accuracy per RD" measurable
against telemetry actuals rather than a retrospective guess. `/cz:audit` asserts every
current-wave WBS leaf has ≥1 RD and every RD has a leaf.
