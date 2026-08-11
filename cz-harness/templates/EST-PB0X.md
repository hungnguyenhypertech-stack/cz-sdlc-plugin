---
kind: EST
agent: planner
rd: null
step: 5
created_at: <RFC3339>
---
<!--
  TEMPLATE: EST-PB0X.md
  Purpose: Roll up three-point estimates from the RD level, up through
  WBS leaves, up to wave totals. The RD is the only place a human/agent
  should originally estimate; everything above that is arithmetic rollup,
  not independent guessing — don't re-estimate at WBS level, sum instead.
-->

# Estimates — PB0X

**Project code:** PB0X
**Status:** <!-- Draft | Approved | Locked -->
**Estimation unit:** hours (h)
**Expected-value formula (PERT-style):** expected_h = (optimistic + 4*likely + pessimistic) / 6

---

## How to use this file

<!-- 1. Every RD carries its own optimistic/likely/pessimistic/expected_h
       in rd-template.yaml's estimate{} block — that is the ONLY place a
       three-point estimate is originally produced.
     2. This file ROLLS UP those RD numbers to their parent WBS leaf, then
       rolls WBS leaves up to their wave total. Do not hand-estimate at
       WBS or wave level; if a WBS leaf has no RD yet (later/next wave,
       epic/feature-level per WBS-PB0X.md), use a rough placeholder ROM
       (rough order of magnitude) clearly marked as such. -->

---

## RD-Level Estimates (source data)

| RD ID | Optimistic (h) | Likely (h) | Pessimistic (h) | Expected (h) | WBS leaf |
|---|---|---|---|---|---|
| RD-PB0X-012.01 | <!-- 4 --> | <!-- 8 --> | <!-- 16 --> | <!-- =(4+32+16)/6=8.7 --> | WBS-PB0X-1.1.1 |
| RD-PB0X-012.02 | | | | | WBS-PB0X-1.1.1 |
| RD-PB0X-013.01 | | | | | WBS-PB0X-1.1.2 |

---

## WBS Leaf Rollup

<!-- Sum of expected_h across all RDs mapped to this leaf. For next/later
     wave leaves with no RDs yet, use a ROM estimate and flag it. -->

| WBS ID | Granularity | RD count | Sum optimistic (h) | Sum likely (h) | Sum pessimistic (h) | Sum expected (h) | Confidence |
|---|---|---|---|---|---|---|---|
| WBS-PB0X-1.1.1 | Task | 2 | <!-- ... --> | <!-- ... --> | <!-- ... --> | <!-- ... --> | High (RD-backed) |
| WBS-PB0X-1.1.2 | Task | 1 | | | | | High (RD-backed) |
| WBS-PB0X-2.1 | Feature | 0 | *ROM only* | *ROM only* | *ROM only* | <!-- e.g. 40 --> | Low (no RDs yet, feature-level per rolling wave) |
| WBS-PB0X-3.1 | Epic | 0 | *ROM only* | *ROM only* | *ROM only* | <!-- e.g. 120 --> | Very low (epic-level placeholder) |

---

## Wave Rollup

| Wave | WBS leaves included | Sum expected (h) | Confidence | Notes |
|---|---|---|---|---|
| Near-term (Wave 1) | WBS-PB0X-1.1.1, WBS-PB0X-1.1.2, ... | <!-- ... --> | High | RD-backed, task-level |
| Next (Wave 2) | WBS-PB0X-2.1, ... | <!-- ... --> | Low | Feature-level ROM, will firm up when wave rolls forward |
| Later (Wave 3) | WBS-PB0X-3.1, ... | <!-- ... --> | Very low | Epic-level placeholder only |

**Project total (sum of all waves):** <!-- ... h --> <!-- flag clearly that later waves are ROM, not committed -->

---

## Variance / Re-estimation Log

<!-- Every time an RD's estimate changes after initial recording (e.g.
     after a red/green cycle reveals it was under/over-estimated), log it
     here so estimation accuracy can be tracked over time (see
     CASE-STUDY.md metrics: rework rate). -->

| Date | RD ID | Old expected (h) | New expected (h) | Reason |
|---|---|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- RD-PB0X-012.01 --> | <!-- 8.7 --> | <!-- 14.2 --> | <!-- e.g. "underestimated auth edge cases, caught in green phase" --> |

---

## Revision History

| Date | Author | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | <!-- name --> | <!-- initial draft --> |
