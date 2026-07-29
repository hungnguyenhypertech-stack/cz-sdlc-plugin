<!--
  TEMPLATE: ARCH-PB0X.md
  Purpose: Record architecture decisions as ADRs. The hard rule this file
  enforces: NEVER record a chosen trade-off without also recording the
  rejected alternative(s) and why they lost. An ADR missing the
  "Rejected Alternatives" column is invalid and should be sent back.
-->

# Architecture Decisions — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->

---

## ADR Index

<!-- Keep this table in sync with the detailed ADR entries below. ADR IDs
     follow ADR-<proj>-<nnn>, monotonically increasing, never reused. -->

| ADR ID | Title | Status | Decision (short) | Rejected Alternatives |
|---|---|---|---|---|
| ADR-PB0X-001 | <!-- e.g. "Points ledger storage engine" --> | Accepted | <!-- e.g. "Postgres with append-only ledger table" --> | <!-- e.g. "Redis (no durable audit trail); Event-sourced Kafka log (over-engineered for MVP volume)" --> |
| ADR-PB0X-002 | | Proposed | | |
| ADR-PB0X-003 | | | | |

---

## ADR Detail Entries

<!-- One block per ADR. Every block MUST include a non-empty "Rejected
     Alternatives" section with at least one real alternative and the
     specific reason it lost — "we didn't think of it" is not a valid
     rejection reason; the option must have been genuinely considered. -->

### ADR-PB0X-001: <!-- Title -->

- **Status:** <!-- Proposed | Accepted | Superseded by ADR-PB0X-0xx -->
- **Date:** <!-- YYYY-MM-DD -->
- **Deciders:** <!-- names -->
- **Context:** <!-- What forced this decision? What constraint or requirement
  triggered it? Reference REQ-PB0X-nnn / NFR-PB0X-nnn if applicable. -->

**Decision:**
<!-- The option that was chosen, stated plainly. -->

**Rationale:**
<!-- Why this option won — tie back to constraints, NFRs, team capability,
     cost, or risk. -->

**Rejected Alternatives:**

| Alternative | Why it was rejected |
|---|---|
| <!-- e.g. "Redis as primary store" --> | <!-- e.g. "No durable audit trail; violates NFR-PB0X-003" --> |
| <!-- e.g. "Event-sourced Kafka log" --> | <!-- e.g. "Operational overhead not justified at current volume; revisit if scale >10x" --> |

**Consequences:**
<!-- What this decision makes easier/harder going forward, and any
     follow-up ADRs it forces. -->

**Revisit trigger:**
<!-- Condition under which this ADR should be reopened, e.g. "if MAU
     exceeds X" or "if compliance requirement Y is introduced." -->

---

### ADR-PB0X-002: <!-- Title -->

- **Status:** <!-- ... -->
- **Date:** <!-- ... -->
- **Deciders:** <!-- ... -->
- **Context:** <!-- ... -->

**Decision:**
<!-- ... -->

**Rationale:**
<!-- ... -->

**Rejected Alternatives:**

| Alternative | Why it was rejected |
|---|---|
| <!-- ... --> | <!-- ... --> |

**Consequences:**
<!-- ... -->

**Revisit trigger:**
<!-- ... -->

<!-- Duplicate the block above for each additional ADR. -->

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
