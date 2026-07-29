# Traceability

Every artifact CZ-Harness produces is addressable by a stable id, and every id participates in
a traceability graph that the RTM (Requirements Traceability Matrix) generator walks. This
document defines the id scheme, the immutability rule, the content-hash freeze mechanism that
decides when a test is trustworthy, and the orphan classes the RTM checks for.

## ID Scheme

| Prefix | Format | Meaning |
|---|---|---|
| `REQ` | `REQ-<proj>-<nnn>` | A top-level requirement, typically stakeholder-facing |
| `RD` | `RD-<proj>-<nnn>.<mm>` | A Requirement Detail — the atomic delivery unit, always a child of one REQ (`nnn` matches the parent REQ, `mm` disambiguates siblings) |
| `AC` | `AC-<proj>-<nnn>.<mm>-<k>` | An acceptance criterion under RD `<nnn>.<mm>`; `k` is the AC's *index* within that RD (1st, 2nd, 3rd AC), not a global ordinal |
| `TC` | `TC-<proj>-<nnn>.<mm>-<k>[N\|P\|F]` | A test case tied to AC index `k` of the same RD. Suffix denotes test *kind*, not a new index: bare = acceptance (happy path), `N` = negative, `P` = permission/role-based, `F` = NFR-performance. Multiple TCs can share the same `k` with different suffixes (e.g., `TC-...-2` and `TC-...-2N` both trace to `AC-...-2`) |
| `WBS` | `WBS-<proj>-<a>.<b>.<c>` | Work breakdown structure node, independent hierarchy from REQ/RD (planning view, not requirements view) |
| `NFR` | `NFR-<proj>-<nnn>` | A non-functional requirement, referenced by RDs via `nfr_refs`, not owned by any single RD |
| `GATE` | `GATE-<rd-id>-<nn>` | A specific gate decision instance for an RD (an RD can pass through the same gate stage more than once across retries; `nn` disambiguates) |
| `HS` | `HS-<proj>-<nnn>` | A hard-stop record — raised when a contradiction is detected, closed only by human action |

The critical detail in the `TC` suffix: `k` always refers back to the AC index it validates,
**never** to the test's own creation order. A test case named `TC-PB04-042.01-2N` is always the
negative-path test for AC #2 of that RD — you can compute which AC any TC belongs to purely
from its id, without a lookup table.

## Immutability

IDs are permanent. Once minted, an id is **never reused**, even after its artifact is removed
from active scope. If an RD is descoped, it transitions to `state: withdrawn` — it is never
deleted from the registry. This matters because:

- Historical telemetry (`telemetry/events.jsonl`) references RD ids, and those events must
  remain resolvable years later for audit purposes.
- A withdrawn RD's id staying reserved prevents a future RD from accidentally reusing an id
  that carries different, stale meaning to anyone who remembers the old one.

## `content_hash` and What It Covers

`content_hash` is computed **only** over the fields that define what "correct" means for an
RD: `statement`, `ac[]`, and `nfr_refs`. It explicitly excludes `estimate`, `assigned_agent`,
`priority`, and any other operational metadata.

The reasoning: editing an estimate or reassigning an agent doesn't change what a passing test
looks like, so it must not invalidate existing test evidence. Editing an AC, by contrast,
changes the definition of correct behavior, so any test derived from the old AC is now
testing the wrong thing and must be flagged.

## The Freeze Rule

Every TC carries an `rd_hash` field — a snapshot of the RD's `content_hash` at the moment the
test was derived. Freshness is computed by comparison:

| TC state | Condition |
|---|---|
| `fresh` | `TC.rd_hash == RD.content_hash` |
| `stale` | `TC.rd_hash != RD.content_hash` (the RD changed since this test was derived) |
| `missing` | An AC exists with no TC at all pointing to it |

**When a normative field changes** (anything covered by `content_hash`), the following
sequence fires automatically, without a human needing to trigger it:

1. `RD.content_hash` changes and `RD.version` increments.
2. Every TC linked to that RD flips to `stale` immediately — this is a pure recomputation, no
   test actually re-runs yet.
3. `guard-rd-freeze` blocks any further writes to that RD's source paths until test-designer
   re-derives the affected tests and produces a fresh red log against the new AC.
4. The RD's own state moves `stale` → back to `red` once re-derivation succeeds, and the
   *prior* evidence chain (old gate records, old telemetry) is retained rather than
   overwritten — the history shows both what passed before and what changed.
5. An `rd_changed` event is written to telemetry recording: who made the change, which fields
   changed, which TC ids went stale, and which downstream RDs (via `nfr_refs` or dependency
   edges) depend on this RD and may themselves need review.

This is the mechanism that prevents "the test still shows green" from being misleading evidence
after a requirement quietly changed underneath it.

## RTM Orphan Classes

The RTM generator checks for seven classes of orphan — an artifact that exists but isn't
properly linked into the traceability graph:

1. **REQ with no RD** — a requirement with nothing delivering against it.
2. **RD with no AC** — an RD accepted without acceptance criteria (should be structurally
   impossible post-validity-check, but the RTM re-verifies).
3. **AC with no TC** — this is the `missing` TC state surfaced at the RTM level.
4. **TC with no RD/AC back-reference** — an orphaned test that claims to validate something
   that no longer resolves.
5. **RD with no WBS mapping** — delivery work with no planning-side counterpart.
6. **NFR with no referencing RD** — a non-functional requirement nobody is actually building
   against.
7. **GATE record with no resolvable RD** — a gate decision pointing at an RD id that isn't in
   the current registry (usually a sign of a bad withdrawal or an id typo, not a legitimate
   withdrawn RD, since withdrawn RDs are retained and remain resolvable).

## Severity by Profile

Orphan detection severity is profile-dependent, not uniform:

| Profile | Behavior on orphan detection |
|---|---|
| Standard | Blocks the RTM report from generating |
| Heavy | Blocks the RTM report from generating |
| Light | Warns only — the report generates with orphans listed, does not fail the run |

This mirrors the general Light-profile posture (see `LIGHTWEIGHT-MODE.md`): Light trades some
rigor for speed, but always by explicit, logged relaxation rather than silent omission.
