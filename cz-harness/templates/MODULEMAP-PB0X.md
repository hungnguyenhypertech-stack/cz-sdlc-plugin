---
kind: MODULEMAP
agent: sa
rd: null
step: 2
created_at: <RFC3339>
---
<!--
  TEMPLATE: MODULEMAP-PB0X.md
  Purpose: Inventory every module in the system and tag it Layer 0 or
  Layer 1. This tagging drives two mechanical decisions elsewhere in the
  harness: (a) how aggressively an RD touching this module can be split
  into parallel sub-RDs, and (b) whether a "red-skip" (skipping the
  failing-test-first step) is ever permitted for this module.
-->

# Module Map — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->

---

## What "Foundation vs Surface" means here

<!-- This section is the load-bearing explanation — keep it even after
     filling in the table, because new team members and agents will read
     this to decide how to treat a module they haven't seen before. -->

**Layer 0 — Hidden Foundation.**
Modules that other modules depend on but that have no direct, independent
user-facing behavior of their own — e.g. auth/session primitives, the
points-ledger data model, shared API clients, migration/schema code,
crypto/signing utilities. Characteristics:
- Failure here silently corrupts or breaks everything built on top.
- Changes are hard to observe directly through UI/AC alone — a green
  checkmark on a surface feature can hide a broken foundation.
- **Consequence for splitting:** Layer 0 RDs should be split conservatively
  (smaller, more sequential) rather than parallelized, because concurrent
  edits to shared foundation code create hidden interference.
- **Consequence for red-skip:** red-skip (skipping the red/failing-test
  step) is **never permitted** on Layer 0 modules — regressions are
  invisible until much later and are disproportionately expensive.

**Layer 1 — Surface.**
Modules that expose behavior directly to a user, API consumer, or another
team's system, and whose correctness is directly observable via
acceptance criteria — e.g. UI components, REST endpoints whose contract
is the AC itself, notification templates, reports. Characteristics:
- Failure here is usually visible immediately (a broken screen, a wrong
  response body).
- **Consequence for splitting:** Layer 1 RDs can be split more freely and
  run in parallel, since blast radius is contained to the feature itself.
- **Consequence for red-skip:** red-skip is still discouraged by default
  but may be permitted for very low-risk, low-hazard Surface RDs per the
  delegation/leash rules in DELEGATION-MAP-PB0X.md — never automatic,
  always a logged exception.

---

## Module Table

<!-- One row per module. "Depends on" should only list other modules in
     this table (keeps the dependency graph closed). Module IDs follow
     MOD-<proj>-<nnn>. -->

| Module ID | Module Name | Layer | Description | Depends on | Owner |
|---|---|---|---|---|---|
| MOD-PB0X-001 | <!-- e.g. "Points Ledger" --> | 0 | <!-- e.g. "Source-of-truth ledger for point accrual/decay" --> | <!-- e.g. none --> | <!-- name --> |
| MOD-PB0X-002 | <!-- e.g. "Auth/Session" --> | 0 | <!-- ... --> | <!-- ... --> | |
| MOD-PB0X-003 | <!-- e.g. "Redemption API" --> | 1 | <!-- e.g. "REST endpoint for converting points to discount code" --> | MOD-PB0X-001, MOD-PB0X-002 | |
| MOD-PB0X-004 | <!-- e.g. "Checkout Widget (UI)" --> | 1 | <!-- ... --> | MOD-PB0X-003 | |
| MOD-PB0X-005 | | | | | |

---

## Layer Summary

| Layer | Module count | Notes |
|---|---|---|
| 0 (Foundation) | <!-- n --> | <!-- e.g. "conservative split, no red-skip" --> |
| 1 (Surface) | <!-- n --> | <!-- e.g. "parallel-friendly, red-skip case-by-case" --> |

---

## Open Questions

<!-- Any module whose layer assignment is ambiguous or contested goes
     here until resolved — don't leave ambiguity silently baked into the
     table above. -->

- <!-- e.g. "Is the notification-template module Layer 0 or 1? It has no
       direct UI but its output is user-visible." -->

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
