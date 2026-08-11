---
kind: DELEGATION-MAP
agent: risk-gov
rd: null
step: 6
created_at: <RFC3339>
---
<!--
  TEMPLATE: DELEGATION-MAP-PB0X.md
  Purpose: Per-RD table of how much autonomy an AI agent has to execute
  that RD without human intervention, and how tightly a human must
  supervise it ("leash"). This is decided PER RD, informed by module
  layer (MODULEMAP), hazard flag (RISK), and RD complexity.
-->

# Delegation Map — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->

---

## Delegation Level Scale

<!-- L0 = most human-involved, L5 = fully autonomous. L5 is restricted by
     CZ-Harness policy and must never actually be granted — it stays
     in the scale for completeness/future-state documentation only. -->

| Level | Meaning | Typical use |
|---|---|---|
| L0 | Human writes/pairs on every line; AI assists only | Highest-hazard, novel, or foundation-critical work |
| L1 | AI drafts, human reviews every diff before commit | Layer 0 modules, first RD of a new module |
| L2 | AI implements, human spot-checks + reviews at gate | Layer 0 routine work, or Layer 1 with hazard flag |
| L3 | AI implements + self-reviews, human reviews at merge gate only | Layer 1 routine work, no hazard flag |
| L4 | AI implements + tests + merges within guardrails, human reviews async/sampled | Low-risk, well-covered Layer 1 work with strong test history |
| L5 | Fully autonomous, no human review | **Not granted.** Policy-restricted — do not assign. Reserved for future/production maturity states only. |

---

## Leash Scale

| Leash | Meaning |
|---|---|
| A | Standard leash — agent proceeds through normal gates (ai_review), human checkpoints at defined gate points only |
| A+ | Tightened leash — additional human checkpoint(s) beyond standard, e.g. mandatory human_review gate before green, or mandatory Understanding Gate re-confirmation mid-RD |

<!-- Rule of thumb: hazard-path risk (RISK-PB0X.md) or Layer 0 module
     (MODULEMAP-PB0X.md) should default to leash A+ regardless of
     delegation level. -->

---

## Per-RD Delegation Table

| RD ID | Module (layer) | Delegation Level | Leash | Rationale |
|---|---|---|---|---|
| RD-PB0X-012.01 | MOD-PB0X-003 (Layer 1) | L3 | A | <!-- e.g. "Routine CRUD endpoint, well-covered by existing test patterns, no hazard flag" --> |
| RD-PB0X-012.02 | MOD-PB0X-003 (Layer 1) | L3 | A | |
| RD-PB0X-012.03 | MOD-PB0X-001 (Layer 0) | L1 | A+ | <!-- e.g. "Touches Points Ledger foundation directly; RISK-PB0X-001 hazard-path applies; every diff reviewed before commit" --> |
| RD-PB0X-013.01 | MOD-PB0X-004 (Layer 1) | L4 | A | <!-- e.g. "Pure UI copy change, low risk, strong existing test coverage" --> |
| RD-PB0X-013.02 | | | | <!-- L5 must never appear in this column — if tempted, use L4 + A+ instead --> |

---

## Escalation / Re-leveling Rule

<!-- Under what conditions does an RD's delegation level get downgraded
     mid-flight (e.g. after a failed gate, an unexpected correction in
     DEVBOOK, or a near-miss on a hazard-path risk)? -->

- Any RD that fails an `ai_review` or `sec_review` gate twice is
  automatically downgraded one delegation level and moved to leash A+
  until closed.
- Any RD touching a hazard-path risk (per RISK-PB0X.md) is capped at L2
  regardless of module layer.
- No RD may be assigned L5 in this project. If this table ever contains
  L5, treat it as a defect in the plan and correct it before proceeding.

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
