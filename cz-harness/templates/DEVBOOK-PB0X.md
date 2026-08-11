---
kind: DEVBOOK
agent: dev
rd: <RD-ID>
step: 8
created_at: <RFC3339>
---
<!--
  TEMPLATE: DEVBOOK-PB0X.md
  Purpose: Per-RD development log. This is the durable record of what the
  AI proposed vs. what a human actually had to correct. Under the
  "Standard" profile, every RD must log at least 1 human-authored
  correction. Under "Heavy" profile, additionally log a root-cause note
  for each correction. If an RD genuinely needed zero corrections, still
  log an entry saying so explicitly (silence is indistinguishable from
  "forgot to log" and both are process failures).
  See devbook-entry-template.md for the single-entry version of this.
-->

# Dev Book — PB0X

**Project code:** PB0X
**Profile in effect:** <!-- Light | Standard | Heavy -->
**Status:** <!-- living document, append-only per RD -->

---

## Profile Rules (reference)

| Profile | Minimum corrections logged per RD | Root-cause note required? |
|---|---|---|
| Light | 0 (optional) | No |
| Standard | >= 1 human-authored correction | No |
| Heavy | >= 1 human-authored correction | **Yes** — root cause required |

<!-- "Human-authored correction" means a human actually edited/rejected/
     redirected AI output — not an AI self-correction, not a rubber-stamp
     approval. If a human reviewed and found nothing to fix, that is NOT
     a correction; log it as "reviewed, no correction needed" instead,
     but note that under Standard/Heavy this may indicate the review was
     too shallow (rubber-stamp risk) — cross-check against
     CASE-STUDY.md's rubber-stamp risk score. -->

---

## RD-PB0X-012.03 — <!-- short title, e.g. "Ledger balance deduction on redeem" -->

- **Delegation level / leash:** <!-- e.g. L1 / A+ (from DELEGATION-MAP-PB0X.md) -->
- **AI proposal (summary):** <!-- what the AI drafted/implemented, in 1-3 sentences -->
- **Human correction made:** <!-- exactly what the human changed and why, e.g. "AI used a non-atomic read-then-write for the balance decrement; human replaced with a single atomic SQL UPDATE ... WHERE balance >= amount to close a race condition" -->
- **Root cause (Heavy profile only):** <!-- e.g. "AI's training pattern defaults to app-level locking; doesn't reach for DB-level atomic guards unless prompted. Add this as a standing instruction for ledger-adjacent RDs." -->
- **Correction author:** <!-- human name --> (human-authored, required)
- **Timestamp:** <!-- YYYY-MM-DDTHH:MM -->
- **Gate reference:** <!-- GATE-RD-PB0X-012.03-01 -->

---

## RD-PB0X-013.01 — <!-- short title -->

- **Delegation level / leash:** <!-- ... -->
- **AI proposal (summary):** <!-- ... -->
- **Human correction made:** <!-- ... -->
- **Root cause (Heavy profile only):** <!-- ... or "N/A — Standard profile" -->
- **Correction author:** <!-- ... -->
- **Timestamp:** <!-- ... -->
- **Gate reference:** <!-- ... -->

<!-- Add one entry block per RD. Never delete or overwrite past entries —
     this file is the audit trail for "did the AI actually need human
     oversight, and what kind." -->

---

## Aggregate Stats (fill in periodically, feeds CASE-STUDY.md metrics)

| Metric | Value |
|---|---|
| Total RDs logged | <!-- n --> |
| RDs with >=1 human correction | <!-- n --> |
| RDs with zero corrections (flag for rubber-stamp review) | <!-- n --> |
| Most common correction category | <!-- e.g. "concurrency/race conditions" --> |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
