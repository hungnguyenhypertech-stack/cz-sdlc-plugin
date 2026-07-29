<!--
  TEMPLATE: SCOPE-PB0X.md
  Purpose: Define what this project IS and IS NOT, and who has authority
  over that boundary. This is the first document produced in a project and
  is the reference all later SPEC/WBS/RTM disputes get resolved against.
  Replace "PB0X" everywhere with the real project code (e.g. PB04).
  Delete all HTML comments once the section is filled in for real; keep
  them in the template file itself.
-->

# Project Scope — PB0X

<!-- One-paragraph plain-English description of the project. No jargon.
     A stakeholder who has never seen this project should understand
     what is being built and why after reading this paragraph. -->

**Project name:** <!-- e.g. "Customer Loyalty Points Revamp" -->
**Project code:** PB0X
**Sponsor:** <!-- name / role of the person who owns the business outcome -->
**Scope owner (PM):** <!-- name of the person with authority to accept/reject scope changes -->
**Date opened:** <!-- YYYY-MM-DD -->
**Status:** <!-- Draft | Approved | Locked -->

---

## 1. Problem Statement

<!-- What business/user problem exists today? Why does it need solving now?
     Avoid solutioning here — describe the pain, not the fix. -->

- Problem: <!-- ... -->
- Evidence / trigger: <!-- data, incident, complaint, strategic directive, etc. -->
- Cost of inaction: <!-- what happens if we do nothing -->

---

## 2. MVP Boundary

<!-- The MVP boundary is the line between "must exist for the first usable
     release" and "can wait." Every item below the line gets deferred to
     a later wave, not cut from the SPEC — it just isn't RD'd yet. -->

**MVP definition (one sentence):** <!-- ... -->

### MVP includes
| # | Capability | Why it's in MVP |
|---|-------------|------------------|
| 1 | <!-- e.g. "User can redeem points for a discount code" --> | <!-- e.g. "Core value prop, unusable without it" --> |
| 2 | | |

### MVP explicitly excludes (deferred, not cancelled)
| # | Capability | Target wave / phase |
|---|-------------|----------------------|
| 1 | <!-- e.g. "Points transfer between accounts" --> | <!-- e.g. "Wave 2 / Phase 2" --> |
| 2 | | |

---

## 3. In Scope

<!-- Concrete, testable statements of what this project WILL deliver.
     These should be traceable forward into SPEC-PB0X.md requirements. -->

- <!-- In-scope item 1 -->
- <!-- In-scope item 2 -->
- <!-- In-scope item 3 -->

---

## 4. Out of Scope

<!-- Explicitly call out adjacent things people might ASSUME are included.
     Being explicit here prevents scope-creep arguments later. Each line
     should anticipate a "wait, doesn't this cover X too?" question. -->

- <!-- Out-of-scope item 1 — reason it's excluded -->
- <!-- Out-of-scope item 2 — reason it's excluded -->
- <!-- Out-of-scope item 3 — reason it's excluded -->

---

## 5. Stakeholders

<!-- List everyone with a stake in scope decisions. RACI-lite: who decides,
     who's consulted, who's just informed. -->

| Name / Role | Interest | RACI | Notes |
|---|---|---|---|
| <!-- e.g. Sponsor --> | <!-- e.g. Owns budget & outcome --> | <!-- R/A/C/I --> | |
| <!-- e.g. Scope owner (PM) --> | <!-- e.g. Runs the harness, accepts RDs --> | A | |
| <!-- e.g. Security lead --> | <!-- e.g. sec_review gate --> | C | |
| <!-- e.g. End users / rep --> | <!-- e.g. Consulted on UX --> | C | |

---

## 6. Assumptions & Constraints

<!-- Anything the scope depends on being true, and any hard constraints
     (budget, deadline, tech stack, compliance) that bound the solution
     space. -->

- Assumption: <!-- ... -->
- Constraint: <!-- ... -->

---

## 7. Change Control

<!-- How does a scope change request get raised, reviewed, and approved?
     Reference the delegation/leash model if changes to scope require
     human sign-off (they always should). -->

Any change to sections 3/4 above requires: <!-- e.g. "sponsor + scope owner sign-off, logged in deliverables/understanding-log/scope.md" -->

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
