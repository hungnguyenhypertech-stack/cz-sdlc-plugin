---
name: sdd-loop
description: Run or reason about cz-harness's strict spec-driven-development (red-green-refactor) inner loop for a single RD. Invoke when building an RD's implementation (test-designer then dev), when deciding whether a src/** write should be allowed or blocked, when explaining why guard-red-before-green.sh or guard-rd-freeze.sh denied a write, or when reviewing a completed RD for the specific failure patterns ai-reviewer is required to hunt for.
---

# SDD Loop (Strict Red-Green-Refactor)

cz-harness enforces one non-negotiable build discipline per RD: no code without a proven
failing test first, no claimed "done" without a byte-identical green re-run, and no
implementation agent ever sees the tests it's supposed to satisfy. This skill packages plan
§8.3's inner loop and `commands/cz-build.md`'s exact step sequence so the discipline can be
followed or explained without re-deriving it from source each time.

## When to use this skill

- Executing `/cz:build <rd-id>` (Phase 8) — this skill IS that command's mechanics, spelled out.
- Deciding whether a `src/**` write should proceed, or diagnosing why it was blocked.
- Explaining to a PM or reviewer why "the test still shows green" isn't sufficient evidence
  by itself, or what `ai-reviewer` is required to flag.

## The inner loop, in order (plan §8.3)

```
  RD in `ready`, dependencies accepted, slot available under max_in_flight
        │
        ▼
  claim  ──▶ state/locks/RD-….lock         [RD: claimed | agent: claimed→planning]
        │
        ▼
  test-designer writes TCs from the AC
        │   dev is not in context; tests/** invisible to dev
        ▼
  RUN TESTS ──▶ must FAIL ──▶ evidence/RD-…/tests-red-vN.log   ◀── RED PROOF
        │       (records the RD hash it was produced against)   [RD: red]
        ▼
  dev implements minimum code to pass
        │   tests/** read-only to dev; RD annotation required in source
        ▼
  RUN TESTS ──▶ must PASS ──▶ tests-green-vN.log               ◀── GREEN PROOF
        │       (test files byte-identical to the red run)      [RD: green]
        ▼
  refactor (optional) ──▶ tests stay green
        │
        ▼
  GATE 1  ai-reviewer     (always)
  GATE 2  sec-reviewer    (hazard / A+ only)
  GATE 3  human approval  (always — Understanding Gate)
        │
        ▼
  telemetry + Dev Book entry ──▶ RD accepted ──▶ release lock ──▶ next RD
```

## The `/cz:build $1` step sequence (strict — no step skipped or reordered)

1. **Claim** — take the lock via `guard-claim-lock.sh "$1"` (the one hook not wired into
   `hooks.json`; it must be invoked directly at claim time). This is what makes the board and
   telemetry show a real acting agent instead of `unknown`, since later hooks resolve identity
   from `state/locks/$1.lock` when no env var survives into that call. Mark the RD `in_progress`
   in `state/board.json`.
2. **Context** — load the RD's statement, AC list, and `content_hash`. `dev` must **never** be
   given `tests/**` contents at any point in this loop.
3. **Delegate (test-designer)** — restamp the lock to `test-designer`, then dispatch it via
   Task with only the RD's AC list. It writes one TC per AC (1–3 TCs) under `tests/**`, each
   tagged with the RD's `content_hash`.
4. **Red proof** — run the new tests. They **must fail** (no implementation exists yet).
   Capture raw output to `evidence/RD-<rd-id>/tests-red-vN.log`, hash-tagged to the
   `content_hash`. If tests pass here, the TC is invalid (testing nothing) — send it back to
   `test-designer`. Once genuine red is confirmed, append a `test_red` telemetry event — this
   is the only reliable signal (besides dispatch noise) that the loop actually reached this
   stage.
5. **Guard** — `guard-red-before-green` blocks any `src/**` write for this RD unless a matching
   red log exists for the current `content_hash`. Do not attempt to bypass it.
6. **Delegate (dev)** — restamp the lock to `dev`, dispatch it via Task with the RD statement
   and AC only (never test contents). `tests/**` is read-only to `dev`. `dev` implements the
   minimum code to satisfy the AC and annotates every touched `src/**` file/function with the
   RD ID (e.g. `// RD-PB01-014.02`) — this annotation is what the orphan check for
   "unannotated src files" verifies later.
7. **Green proof** — run the same tests again. They **must pass**, and the test file bytes must
   be **byte-identical** to the red run (diff the source, not just re-run it) — if a TC was
   edited between red and green, the loop is invalid and must restart from step 3. `guard-rd-
   freeze` blocks writes if a linked TC goes stale mid-loop. Once confirmed, append a
   `test_green` telemetry event.
8. **Refactor (optional)** — `dev` may refactor as long as tests stay green on every save;
   re-run tests after each pass. Lock stays stamped `dev`.
9. **DEVBOOK** — restamp the lock back to `cz-build`, then write/append
   `deliverables/DEVBOOK-<rd-id>.md`: red log path, green log path, files touched, refactor
   notes, and the `content_hash` used throughout (see the `devbook` skill for entry content).
10. **Handoff** — this command does not self-gate. It ends by handing off to `/cz:gate $1` (see
    the `gate-engine` skill).

Exit condition: a green run byte-identical in test source to the red run, DEVBOOK written,
control handed to `/cz:gate`.

## The two enforcing hooks

- **`guard-red-before-green.sh`** — PreToolUse hook on any `Write`/`Edit` into `src/**`.
  Resolves which RD owns the write (prefers the active claim lock over grepping the target
  file's own annotations, since a shared file can carry several RDs' annotations and would
  otherwise always resolve to whichever appears first). Allows the write only if: the RD state
  is `claimed`/`red` (initial build) or `green`+ (refactor, requiring the red log to still
  exist); AND a red log exists at the recorded path; AND that log's content matches the RD's
  current `content_hash`; AND the log records a genuine failure (not, say, a collection/import
  error masquerading as red). Anything else is denied with a specific reason.
- **`guard-rd-freeze.sh`** — PreToolUse hook that blocks all `src/**` writes for an RD while it
  is `state: stale`, or while any TC linked in the RD's `tests:` list has a recorded `rd_hash`
  that no longer matches the RD's current `content_hash`. The only way through is
  `test-designer` re-deriving the affected tests and producing a fresh red log. See the
  `traceability` skill for the freeze rule this enforces.

Together these are the fail-closed core of the loop — *"if it cannot be verified, it is
blocked by default"* as executable policy, not a review-time reminder.

## What `ai-reviewer` hunts for (gate 1, always runs)

Generic "review this code" prompts produce generic praise, so the checklist is specific.
`ai-reviewer` must state pass/fail explicitly on each:

- Tautological or vacuous assertions in tests (e.g. `expect(true).toBe(true)`).
- Tests that would pass against an empty/stub implementation.
- Acceptance criteria (AC) with no corresponding TC.
- Stale TC links (a TC referencing an AC that's since changed or been removed).
- Silent drift between the RD statement and what was actually implemented.
- Swallowed exceptions (try/catch that discards errors instead of handling them).
- `TODO`/`FIXME` markers in an RD marked done.
- Red proof absent, stale, or trivially different from the green run.
- Source files with no RD annotation.
- `red_skipped: true` recorded on anything that shouldn't have qualified for the Light-profile
  skip exception.

`ai-reviewer` is read-only by construction (L0 — its only power is to write a report); it never
fixes what it reviews, never reviews its own prior output without fresh reassessment, and never
writes `human_approved: true` — approval is exclusively a human action downstream in the gate
engine (see the `gate-engine` skill).

CASAN §11.4 advises combining 2–3 validation types by risk level; this loop combines
deterministic rules (hooks, hashes, test runs) + LLM-as-judge (`ai-reviewer`) + human
validation — the full set.
