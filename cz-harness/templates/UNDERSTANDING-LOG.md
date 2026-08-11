---
kind: EXPLAIN
agent: agentops
rd: null
step: n/a
created_at: <RFC3339>
---
<!--
  TEMPLATE: UNDERSTANDING-LOG.md
  Purpose: Append-only log of "Understanding Gate" questions and their
  answers, plus Delivery Log narrative entries. The Understanding Gate is
  a checkpoint where the AI must ask a clarifying question before
  proceeding on ambiguous work, and the answer MUST be human-authored —
  an AI answering its own question here defeats the entire purpose of
  the gate and should be treated as a process violation, not logged as
  a valid entry.

  FRAGMENT FILE, NOT A SINGLE PROJECT-WIDE LOG: as of this version, this
  template is instantiated once per phase gate (deliverables/understanding-
  log/<phase>.md — e.g. init.md, scope.md, spec.md, rd-commits.md,
  report.md, audit.md, rebuild-state.md, viva.md) and once per RD
  (deliverables/understanding-log/rd/<rd-id>.md, written by /cz:dor and
  /cz:gate). Each fragment is owned by exactly one phase or one RD, so
  concurrent RDs (under bounded/wave concurrency) never write the same
  file — this is what fixes a real incident where two RDs' concurrent
  DoR reviews raced on a single shared UNDERSTANDING-LOG.md and silently
  lost the file's entire prior history to a last-write-wins overwrite.
  UL-<nnn> numbering is FRAGMENT-LOCAL (restart at UL-001 in every new
  fragment) — do not try to maintain one global counter across fragments,
  that reintroduces the same kind of shared-state race this split exists
  to remove. To read the whole project's understanding log, read every
  file under deliverables/understanding-log/** (see /cz:viva step 1).
-->

# Understanding Log

**Status:** append-only, never edit or delete past entries *within this fragment*. This file covers one phase or one RD only — see the fragment-file note above.
**Rule:** the "Answer" field in every entry below must be authored by a
human. If no human is available to answer, the entry stays OPEN and the
associated RD/phase stays blocked — the AI must not fill in a plausible
answer itself and proceed.

---

## Entry Format

<!-- Copy this block for every new Understanding Gate question. -->

### UL-<nnn> — Phase/RD: <!-- e.g. "RD-PB0X-012.03" or "Phase 1 kickoff" -->

- **Timestamp asked:** <!-- YYYY-MM-DDTHH:MM -->
- **Asked by:** <!-- agent/session id -->
- **Understanding Gate question:**
  <!-- The exact question the AI asked because it could not proceed
       confidently without clarification. Should be specific, not generic
       ("What should happen if the user has zero points and tries to
       redeem?" not "Any special cases?"). -->

- **Human-authored answer:**
  <!-- MUST be written by a human. If this field contains AI-generated
       text, the entry is invalid — flag and redo. -->

- **Answered by:** <!-- human name, required -->
- **Timestamp answered:** <!-- YYYY-MM-DDTHH:MM, or "OPEN" if unanswered -->
- **Status:** <!-- OPEN | ANSWERED | SUPERSEDED -->

---

## UL-001 — Phase/RD: RD-PB0X-012.03

- **Timestamp asked:** <!-- YYYY-MM-DDTHH:MM -->
- **Asked by:** <!-- e.g. agent-session-4471 -->
- **Understanding Gate question:**
  <!-- e.g. "The SPEC says points expire after 12 months, but doesn't
       say whether redemption should be blocked mid-expiry-check or
       allowed with a warning. Which behavior is correct?" -->

- **Human-authored answer:**
  <!-- e.g. "Block redemption entirely if any portion of the points
       being redeemed would include expired points. Do not partially
       allow it. -- [name]" -->

- **Answered by:** <!-- name -->
- **Timestamp answered:** <!-- YYYY-MM-DDTHH:MM -->
- **Status:** ANSWERED

---

## UL-002 — Phase/RD: <!-- ... -->

- **Timestamp asked:** <!-- ... -->
- **Asked by:** <!-- ... -->
- **Understanding Gate question:**
  <!-- ... -->

- **Human-authored answer:**
  <!-- ... -->

- **Answered by:** <!-- ... -->
- **Timestamp answered:** <!-- ... -->
- **Status:** <!-- ... -->

<!-- Continue numbering UL-003, UL-004, ... sequentially across the whole
     project, never reuse or renumber. -->

---

## Open Questions Index (quick scan)

<!-- Maintain a running list of anything still OPEN so nothing gets lost
     in a long append-only log. -->

| UL ID | Phase/RD | Status | Blocking? |
|---|---|---|---|
| <!-- UL-003 --> | <!-- ... --> | OPEN | <!-- Yes, blocks RD-PB0X-014.01 --> |
