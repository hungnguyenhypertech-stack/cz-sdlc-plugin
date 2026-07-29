<!--
  TEMPLATE: SPEC-PB0X.md
  Purpose: Coarse (project-level, not RD-level) requirements. Each
  requirement gets a stable ID: REQ-<proj>-<nnn> (e.g. REQ-PB04-012).
  These IDs are the anchor that RTM-PB0X.md checks against ("REQ-no-RD"
  orphan class = a REQ here with no RD ever created against it).
  Requirements here are still coarse — they get decomposed into RDs
  (see rd-template.yaml) during WBS/estimation, not written as RDs here.
-->

# Specification — PB0X

**Project code:** PB0X
**Source of truth for scope:** SCOPE-PB0X.md
**Status:** <!-- Draft | Approved | Locked -->

<!-- Numbering convention: REQ-PB0X-001, REQ-PB0X-002, ... never reuse a
     retired number. If a requirement is dropped, mark it "Superseded" or
     "Withdrawn" below rather than deleting the row — RTM needs the trail. -->

---

## How to read this document

<!-- Each requirement below must have:
     1. Statement — a single testable sentence ("The system shall ...")
     2. Rationale — why this requirement exists (ties back to SCOPE problem stmt)
     3. Linked NFRs — non-functional constraints that apply (perf, security,
        availability, a11y, etc.) referenced by NFR-<proj>-<nnn> ids defined
        in the NFR register below.
     Do NOT put acceptance criteria here — AC lives at the RD level in
     rd-template.yaml. This doc is one layer coarser than that. -->

---

## Requirements

### REQ-PB0X-001
<!-- Example fully-filled requirement for reference — replace with real content -->
- **Statement:** The system shall allow a registered user to redeem accumulated loyalty points for a discount code at checkout.
- **Rationale:** Directly addresses the MVP problem statement (SCOPE §1) — redemption is the core value proposition driving retention.
- **Linked NFRs:** NFR-PB0X-001 (response time), NFR-PB0X-003 (audit logging)
- **Status:** Approved
- **Owner:** <!-- name -->

### REQ-PB0X-002
- **Statement:** <!-- "The system shall ..." -->
- **Rationale:** <!-- why -->
- **Linked NFRs:** <!-- NFR-PB0X-00x, ... or "None" -->
- **Status:** <!-- Draft | Approved | Superseded | Withdrawn -->
- **Owner:** <!-- name -->

### REQ-PB0X-003
- **Statement:** <!-- ... -->
- **Rationale:** <!-- ... -->
- **Linked NFRs:** <!-- ... -->
- **Status:** <!-- ... -->
- **Owner:** <!-- ... -->

<!-- Add more REQ-PB0X-NNN blocks as needed. Keep numbering contiguous. -->

---

## Non-Functional Requirements (NFR) Register

<!-- NFRs are cross-cutting constraints referenced by REQs above and by
     individual RDs' nfr_refs[] field. Define them once here. -->

| NFR ID | Category | Statement | Threshold / Metric |
|---|---|---|---|
| NFR-PB0X-001 | Performance | <!-- e.g. "Redemption API responds within..." --> | <!-- e.g. "p95 < 400ms" --> |
| NFR-PB0X-002 | Security | <!-- e.g. "Points balance mutations require..." --> | <!-- e.g. "audit trail, no silent overwrite" --> |
| NFR-PB0X-003 | Auditability | <!-- ... --> | <!-- ... --> |
| NFR-PB0X-004 | Accessibility | <!-- ... --> | <!-- ... --> |

---

## Requirements Summary Table

<!-- Quick-scan index — must stay in sync with the detailed blocks above.
     RTM-PB0X.md is generated FROM this table plus the RD/WBS layers, so
     keep IDs exact and consistent. -->

| REQ ID | Short Title | Status | Linked NFRs |
|---|---|---|---|
| REQ-PB0X-001 | <!-- e.g. Point redemption at checkout --> | Approved | NFR-PB0X-001, NFR-PB0X-003 |
| REQ-PB0X-002 | | | |
| REQ-PB0X-003 | | | |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
