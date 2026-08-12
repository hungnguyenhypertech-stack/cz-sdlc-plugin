---
name: devbook
description: Author or evaluate a Dev Book entry for cz-harness. Invoke when writing deliverables/DEVBOOK-<rd-id>.md at the end of a build loop, when deciding whether an entry satisfies its profile's correction-floor requirement, or when explaining why an empty correction section is a rubber-stamp risk signal rather than a clean pass.
---

# Dev Book

The Dev Book is cz-harness's mechanism for pillar 1 (AI Literacy): every RD gets an entry
recording what the AI proposed, what a human actually changed and why, and — at the Heavy
profile — the root cause behind why the model produced the flawed pattern in the first place.
This skill packages `templates/devbook-entry-template.md` and the correction-floor rules from
plan §2/§8.4 so an entry can be authored or evaluated to spec.

## When to use this skill

- Writing/appending `deliverables/DEVBOOK-<rd-id>.md` at the end of `/cz:build` (step 9 of the
  sdd-loop, see the `sdd-loop` skill).
- Judging whether an existing Dev Book entry meets its Dev Book profile's correction floor
  before an RD can gate.
- Explaining to a PM why "the AI got it right first try" needs to be written down explicitly
  rather than left blank, and why that specific pattern is itself a signal worth tracking.

## Entry structure (one block per RD, merged into `DEVBOOK-PB0X.md`)

1. **RD ID** — the RD this entry documents; must exist in the registry and be referenced from
   the project Dev Book.
2. **Dev Book profile in effect** — Light | Standard | Heavy. Since 1.0.26 this is the RD's own
   `profile:` field if set (an RD-level downgrade — see `skills/rd-decomposition/SKILL.md`'s
   complexity heuristic and `hooks/lib/common.sh`'s `cz_effective_profile`), else the
   module/project profile. Standard/Heavy require ≥1 human-authored correction below; Heavy
   additionally requires Root Cause to be filled in.
3. **What AI Proposed** — concrete description of what the AI generated/implemented before any
   human correction. Reference the actual approach/code pattern, not "implemented the
   feature." Example: *"AI implemented the point-redemption deduction as two separate database
   calls: a SELECT to read the current balance, followed by an UPDATE to write the new balance
   computed in application code."*
4. **The Human Correction Made** — **must be authored by a human**, describing exactly what
   was changed and why. This is the field that makes the entry valid under Standard/Heavy — an
   empty or AI-authored version does not satisfy the requirement. Example: *"Replaced the
   two-step SELECT+UPDATE with a single atomic SQL statement: `UPDATE ledger SET balance =
   balance - :amount WHERE user_id = :uid AND balance >= :amount`, checking the affected-row
   count to detect insufficient balance. This closes a race condition where two concurrent
   redemptions could both read the same starting balance and cause the ledger to go negative."*
   Includes a **Correction author (human, required)** field — a name, not a role.
5. **Why / Root Cause** (required if profile = Heavy) — explains the underlying reason the AI
   produced the flawed/incomplete output, not just what was wrong but *why the model tended
   toward that pattern*. This is what turns a one-off fix into a reusable lesson feeding
   `CASE-STUDY.md`'s lessons-learned, and can become a standing instruction for future RDs on
   similar modules. Example: *"The model's default pattern for 'update a counter' problems is
   app-level read-modify-write, because that's the most common pattern in its training
   distribution for non-concurrent contexts. It doesn't proactively reach for DB-level atomic
   guards unless the prompt explicitly flags concurrency as a concern. Fix: add a standing
   instruction for any RD touching MOD-PB0X-001 (Points Ledger, Layer 0) to explicitly require
   atomic/concurrency-safe writes in the RD statement itself."* If profile is Light or
   Standard, write *"N/A — root cause not required at this profile level"* instead of leaving
   it blank.
6. **Metadata table** — Timestamp, Gate reference (e.g. `GATE-RD-PB0X-012.03-01`), Delegation
   level / leash at time of entry (e.g. `L1 / A+`).

## The correction floor by profile (plan §8.4)

| Dev Book entry requirement | **Light** | **Standard** | **Heavy** |
|---|---|---|---|
| Baseline | per RD | per RD + ≥1 correction | per RD + correction + root cause |

This is a **CZ-Harness extension**, not a baseline requirement — the baseline pipeline asks for
Dev Book evidence per meaningful build step, not a tallied minimum per RD. The per-RD floor
exists at this finer granularity for the same reason the per-RD Understanding Gate exists: at
50–150 RDs per slice, step-level checkpoints alone leave most of the actual work unexamined.

## If truly zero correction was needed

The template is explicit: if an RD genuinely required zero human correction, write that
explicitly in the correction section rather than leaving it blank — **and note that this may
indicate a rubber-stamp review risk**, cross-referencing `CASE-STUDY.md`'s metric for it,
rather than treating a zero-correction entry as simply a clean pass.

This ties directly into cz-harness's one original contribution, the **rubber-stamp risk
score** (plan §2.1):

```
rubber_stamp_risk = f( human_review_minutes per 1k AI output tokens,
                       corrections_logged per RD,
                       gate_pass_on_first_attempt_rate,
                       seconds between artifact_ready and human_approval )
```

High AI volume, near-zero human minutes, zero corrections, and instant approvals score high on
this. It's advisory and surfaced to the PM first — a self-check mirror, not a surveillance
tool — but a Dev Book entry with an unexplained empty correction section is exactly the raw
signal that score is built from. The Orchestrator Guide's framing: *"A learner with 30 real AI
corrections is not the same as a learner with zero corrections. The second case is often
hidden rubber-stamping."*

## Ownership and mechanism

Pillar 1 (AI Literacy) ties the Dev Book to the same enforcement family as the per-phase/per-RD
Understanding Gate: *"Dev Book requires ≥1 human-authored correction per RD (Standard+)."* The
metric this produces is corrections-per-RD, rolled up alongside Understanding Gates
answered/RDs accepted. `/cz:build` writes/appends the entry at step 9 of its loop (see the
`sdd-loop` skill); `/cz:gate` references the Gate reference id back into it at step 9 of its own
sequence (see the `gate-engine` skill).
