<!--
  TEMPLATE: CASE-STUDY.md
  Purpose: End-of-project narrative. Written once, at project close (or
  major milestone close), to capture what actually happened, what the
  harness mechanisms caught vs missed, and quantified outcomes. This is
  the artifact used to justify/tune the harness for the NEXT project.
-->

# Case Study — PB0X

**Project code:** PB0X
**Project name:** <!-- ... -->
**Period covered:** <!-- start date -- end date -->
**Author:** <!-- name -->

---

## 1. Problem

<!-- Restate the original problem from SCOPE-PB0X.md §1 in past tense,
     plus any way the understanding of the problem shifted during
     delivery. -->

<!-- ... -->

---

## 2. Approach

<!-- How was the project actually run? Summarize wave structure, module
     split (layer 0 vs 1), delegation levels used, profile (Light/
     Standard/Heavy). Note any deviation from the original plan and why. -->

- Waves executed: <!-- e.g. "3 waves over 8 weeks" -->
- Dev Book profile used: <!-- Light | Standard | Heavy -->
- Dominant delegation level(s): <!-- e.g. "mostly L3 on Layer 1, L1-L2 on Layer 0" -->

---

## 3. What CZ-Harness Mechanisms Fired — and What They Caught

<!-- This is the core of the case study: concrete instances where a
     harness mechanism (Understanding Gate, DoR, gates, DEVBOOK
     correction logging, RTM orphan checks, hazard-path leash, red-skip
     ban on Layer 0) actually prevented or caught a problem. Vague claims
     like "the process helped" are not acceptable here — cite RD/UL/RISK/
     GATE IDs. -->

| Mechanism | Instance (with ID reference) | What it caught | Would it have been missed otherwise? |
|---|---|---|---|
| Understanding Gate | <!-- UL-001 --> | <!-- e.g. "clarified partial-expiry redemption behavior before code was written" --> | <!-- e.g. "yes — AI's default assumption was the opposite behavior" --> |
| DoR per-RD check | <!-- RD-PB0X-014.01 --> | <!-- e.g. "caught missing dependency link before RD was claimed" --> | |
| ai_review / sec_review gate | <!-- GATE-RD-PB0X-012.03-01 --> | <!-- e.g. "flagged non-atomic ledger write" --> | |
| DEVBOOK correction log | <!-- RD-PB0X-012.03 --> | <!-- e.g. "surfaced a systematic AI blind spot on DB-level atomicity" --> | |
| RTM orphan check | <!-- e.g. "AC-no-TC on RD-PB0X-013.02" --> | <!-- e.g. "caught an AC that was never actually tested before it reached green" --> | |
| Red-skip ban on Layer 0 | <!-- MOD-PB0X-001 --> | <!-- e.g. "forced a real failing test for a ledger change that looked trivial but wasn't" --> | |
| Hazard-path leash (A+) | <!-- RISK-PB0X-001 --> | <!-- ... --> | |

### Notable near-misses / gaps
<!-- Anything the harness should have caught but didn't, or caught late.
     Be honest here — this section is what makes the case study useful
     for improving the harness rather than just a success story. -->

- <!-- ... -->

---

## 4. Metrics

<!-- Quantify outcomes. Define each metric's calculation once, then fill
     in the value, so future case studies are comparable. -->

| Metric | Definition | Value |
|---|---|---|
| Compression ratio | <!-- e.g. "human hours that would have been needed for fully-manual delivery / actual human hours logged" --> | <!-- e.g. "4.2x" --> |
| Token efficiency | <!-- e.g. "accepted RDs / total AI tokens consumed (in thousands)" --> | <!-- e.g. "0.6 RD per 1k tokens" --> |
| Rework rate | <!-- e.g. "RDs requiring re-estimation or re-opening after acceptance / total accepted RDs" --> | <!-- e.g. "12%" --> |
| Rubber-stamp risk score (start) | <!-- e.g. "% of gate reviews with zero corrections logged, week 1" --> | <!-- e.g. "35%" --> |
| Rubber-stamp risk score (end) | <!-- same metric, final week --> | <!-- e.g. "8%" --> |
| Rubber-stamp risk score trend | <!-- direction and interpretation --> | <!-- e.g. "declining — reviewers engaged more deeply as Dev Book habit formed" --> |

---

## 5. Lessons Learned

<!-- What should the NEXT project do differently because of this one?
     Tie each lesson to a concrete mechanism or process change, not a
     vague sentiment. -->

| # | Lesson | Recommended change for next project |
|---|---|---|
| 1 | <!-- e.g. "Layer 0 modules took 2x longer than estimated" --> | <!-- e.g. "pad Layer 0 estimates by 1.5x pessimistic multiplier by default" --> |
| 2 | | |
| 3 | | |

---

## 6. Sign-off

| Role | Name | Date |
|---|---|---|
| PM / Scope owner | <!-- ... --> | <!-- ... --> |
| Sponsor | <!-- ... --> | <!-- ... --> |
