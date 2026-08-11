---
kind: RISK
agent: risk-gov
rd: null
step: 6
created_at: <RFC3339>
---
<!--
  TEMPLATE: RISK-PB0X.md
  Purpose: Risk register for the project. Every risk gets likelihood,
  impact, mitigation, and a hazard-path flag. "Hazard-path" risks are
  ones that, if they materialize, can trigger the project's hard-stop
  conditions (see DELEGATION-MAP-PB0X.md and RD hazard field) — flag
  these distinctly since they change delegation/leash defaults for any
  RD that touches them.
-->

# Risk Register — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->
**Review cadence:** <!-- e.g. "revisited every WEEKLY-PB0X.md cycle" -->

---

## Scoring Legend

| Likelihood | Meaning | Impact | Meaning |
|---|---|---|---|
| L (Low) | <25% chance this wave | L (Low) | Minor rework, <1 day slip |
| M (Medium) | 25-60% chance this wave | M (Medium) | Feature-level delay, budget dent |
| H (High) | >60% chance this wave | H (High) | Wave/milestone slip, hard-stop candidate |

**Hazard-path flag:** Yes/No — a risk is hazard-path if its materialization
would trip a project hard-stop (e.g. data loss, security breach, compliance
violation, irreversible external action). Hazard-path risks force any RD
under them to default to a stricter leash (see DELEGATION-MAP-PB0X.md) and
disallow red-skip regardless of module layer.

---

## Risk Table

| Risk ID | Description | Likelihood | Impact | Mitigation | Hazard-path? | Owner | Status |
|---|---|---|---|---|---|---|---|
| RISK-PB0X-001 | <!-- e.g. "Points ledger migration could double-credit users if run twice" --> | M | H | <!-- e.g. "Idempotency key on migration script; dry-run in staging with prod-size data snapshot" --> | **Yes** | <!-- name --> | Open |
| RISK-PB0X-002 | <!-- e.g. "Third-party discount-code vendor API has no sandbox, testing is limited" --> | H | M | <!-- e.g. "Mock the vendor contract; schedule one paid live test before go-live" --> | No | | Open |
| RISK-PB0X-003 | <!-- e.g. "Key SME unavailable during weeks 3-4" --> | M | M | <!-- e.g. "Front-load Understanding Gate questions before they go on leave" --> | No | | Open |
| RISK-PB0X-004 | | | | | | | |

---

## Hazard-Path Risks (rollup view)

<!-- Duplicate/filter view so hazard risks are never buried in the full
     table above — anyone scanning this file should see these instantly. -->

| Risk ID | Description | Which module(s)/RDs affected | Mitigation | Trigger condition for hard-stop |
|---|---|---|---|---|
| RISK-PB0X-001 | <!-- ... --> | MOD-PB0X-001 (Points Ledger) | <!-- ... --> | <!-- e.g. "any unexplained ledger balance delta > 0 in prod" --> |

---

## Retired / Closed Risks

<!-- Don't delete rows when a risk is resolved — move them here with the
     closure reason, for audit trail. -->

| Risk ID | Description | Closure date | Closure reason |
|---|---|---|---|
| <!-- e.g. RISK-PB0X-000 --> | <!-- ... --> | <!-- YYYY-MM-DD --> | <!-- e.g. "mitigation verified in prod, no recurrence after 2 waves" --> |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
