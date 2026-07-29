<!--
  TEMPLATE: DOR-PB0X.md
  Purpose: Definition of Ready checklist. This is evaluated PER RD, not
  once for the whole project — copy the checklist block for every RD
  before it can be claimed/assigned to an agent. An RD that fails any
  item here is NOT ready and must be sent back for clarification.
-->

# Definition of Ready — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->

---

## DoR Checklist (apply once per RD — copy the block below for each RD)

<!-- Do not water this down to a single project-level checkbox. Every RD
     must be individually assessed because readiness is a property of the
     RD, not the project. An RD that "inherits" readiness from a sibling
     RD is a process violation. -->

### RD-PB0X-<nnn>.<vv> — <!-- short title -->

| # | Check | Pass/Fail | Evidence / notes |
|---|---|---|---|
| 1 | Has at least one Acceptance Criterion (AC) in Given/When/Then form | <!-- Pass/Fail --> | <!-- e.g. "3 ACs defined, see rd yaml ac[]" --> |
| 2 | Has a three-point estimate within the module's normal bounds (no wild outliers vs similar past RDs) | | <!-- e.g. "8.7h expected, in line with similar redemption-API RDs" --> |
| 3 | Maps to exactly one module in MODULEMAP-PB0X.md | | <!-- e.g. "MOD-PB0X-003" --> |
| 4 | Dependencies (depends_on[]) identified and either resolved or explicitly sequenced | | <!-- e.g. "depends_on: RD-PB0X-012.01 (ledger read API), status: done" --> |
| 5 | Parent requirement (parent_req) linked to a valid REQ-PB0X-nnn | | |
| 6 | WBS leaf assigned (wbs field points to a real WBS-PB0X-a.b.c leaf) | | |
| 7 | Hazard flag evaluated (true/false) and, if true, delegation/leash set per DELEGATION-MAP-PB0X.md | | |
| 8 | NFR references (nfr_refs[]) checked against SPEC-PB0X.md NFR register | | |

**Overall verdict:** <!-- READY / NOT READY -->
**If NOT READY, blocking reason(s):** <!-- ... -->
**Evaluated by:** <!-- name/agent -->
**Date:** <!-- YYYY-MM-DD -->

---

<!-- Duplicate the block above for every RD. Keep them append-only in this
     file (or split into per-RD files if the project is large) so there's
     a durable record of what passed DoR and when. -->

### RD-PB0X-<nnn>.<vv> — <!-- next RD -->

| # | Check | Pass/Fail | Evidence / notes |
|---|---|---|---|
| 1 | Has AC in Given/When/Then form | | |
| 2 | Estimate within bounds | | |
| 3 | Maps to one module | | |
| 4 | Dependencies identified | | |
| 5 | Parent requirement linked | | |
| 6 | WBS leaf assigned | | |
| 7 | Hazard flag evaluated | | |
| 8 | NFR references checked | | |

**Overall verdict:**
**Evaluated by:**
**Date:**

---

## DoR Failure Log (aggregate)

<!-- Track RDs that failed DoR and why — patterns here (e.g. "always
     missing AC") indicate an upstream authoring problem worth fixing. -->

| RD ID | Failed check(s) | Resolution | Re-evaluated on |
|---|---|---|---|
| <!-- RD-PB0X-014.01 --> | <!-- e.g. "#4 - dependency not yet closed" --> | <!-- e.g. "waited for RD-PB0X-013.02 to close" --> | <!-- YYYY-MM-DD --> |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
