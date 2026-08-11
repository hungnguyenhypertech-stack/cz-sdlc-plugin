---
kind: WBS
agent: planner
rd: null
step: 4
created_at: <RFC3339>
---
<!--
  TEMPLATE: WBS-PB0X.md
  Purpose: Break the project down into a Work Breakdown Structure using
  ROLLING-WAVE planning. Every leaf node gets an ID: WBS-<proj>-<a>.<b>.<c>
  (e.g. WBS-PB04-1.2.3). Leaves are the level that RDs attach to
  (rd-template.yaml field "wbs").
-->

# Work Breakdown Structure — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->
**Planning horizon:** <!-- e.g. "8-week project, 3 waves" -->

---

## Rolling-Wave Depth Rule

<!-- This is the governing rule for how deep to decompose each part of the
     WBS depending on how far away in time it is. Do NOT decompose distant
     work to task-level — it will be wrong by the time you get there and
     wastes planning effort. Re-decompose each wave as it becomes "near-term." -->

| Wave | Time horizon | Required decomposition depth | Leaf granularity |
|---|---|---|---|
| Near-term (current wave) | <!-- e.g. "next 1-2 weeks" --> | Task-level | Each leaf = one RD-sized unit of work, estimable in hours |
| Next wave | <!-- e.g. "weeks 3-4" --> | Feature-level | Each leaf = a feature grouping; decompose to task-level only when it becomes near-term |
| Later waves | <!-- e.g. "weeks 5+" --> | Epic-level | Each leaf = an epic/theme; placeholder only, re-planned each wave-turnover |

<!-- When a wave rolls forward (e.g. "next" becomes "near-term"), this file
     must be re-edited to decompose that wave one level deeper. Log the
     re-decomposition in the revision history at the bottom. -->

---

## WBS Tree

<!-- ID scheme: WBS-PB0X-<phase>.<epic/feature>.<task>
     e.g. WBS-PB0X-1.2.3 = Phase 1, Epic/Feature 2, Task 3.
     Only fully task-level leaves in the near-term wave get a hard estimate
     in EST-PB0X.md; feature/epic-level leaves get rough order-of-magnitude
     placeholders until decomposed. -->

### WBS-PB0X-1 — <!-- Phase 1 name, e.g. "Points Redemption MVP" --> (Near-term wave)

- **WBS-PB0X-1.1** — <!-- Feature, e.g. "Redemption API" -->
  - **WBS-PB0X-1.1.1** — <!-- Task, e.g. "Implement POST /redeem endpoint" --> — *Leaf — task-level* — maps to RD-PB0X-<nnn>.<vv>
  - **WBS-PB0X-1.1.2** — <!-- Task --> — *Leaf — task-level* — maps to RD-PB0X-<nnn>.<vv>
- **WBS-PB0X-1.2** — <!-- Feature -->
  - **WBS-PB0X-1.2.1** — <!-- Task --> — *Leaf — task-level*
  - **WBS-PB0X-1.2.2** — <!-- Task --> — *Leaf — task-level*

### WBS-PB0X-2 — <!-- Phase 2 name --> (Next wave — feature-level only)

- **WBS-PB0X-2.1** — <!-- Feature --> — *Leaf — feature-level, NOT yet decomposed to tasks*
- **WBS-PB0X-2.2** — <!-- Feature --> — *Leaf — feature-level, NOT yet decomposed to tasks*

### WBS-PB0X-3 — <!-- Phase 3 name --> (Later wave — epic-level only)

- **WBS-PB0X-3.1** — <!-- Epic/theme, e.g. "Points transfer & social features" --> — *Leaf — epic-level placeholder*

---

## Leaf Index (flat list for cross-reference with EST/RTM)

| WBS ID | Title | Wave | Granularity | Linked RD(s) | Module (from MODULEMAP) |
|---|---|---|---|---|---|
| WBS-PB0X-1.1.1 | <!-- ... --> | Near-term | Task | RD-PB0X-012.01 | MOD-PB0X-003 |
| WBS-PB0X-1.1.2 | | Near-term | Task | | |
| WBS-PB0X-1.2.1 | | Near-term | Task | | |
| WBS-PB0X-2.1 | | Next | Feature | *(not yet — decompose when wave rolls forward)* | |
| WBS-PB0X-3.1 | | Later | Epic | *(not yet)* | |

---

## Revision History

<!-- Log every wave-rollover re-decomposition here, not just content edits. -->

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft, wave 1 decomposed to task-level --> |
