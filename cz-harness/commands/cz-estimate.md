---
description: Phase 5 — roll up three-point RD estimates into a project-level estimate
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task, Bash
---

Phase 5 of the cz-harness playbook. Project code `$1`. Output artifact: `deliverables/EST-$1.md`.

**Gate check**: refuse unless `gate-records/PB4-wbs.json` is `status:"passed"`. Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/EST-*.md` unless that gate record already shows `status:"passed"` on disk.

7-beat loop:

1. **Context** — load `deliverables/WBS-$1.md` near-term wave leaves, and any RDs already drafted under `rd/` for those leaves (RDs carry `estimate.optimistic_h`, `estimate.expected_h`, `estimate.pessimistic_h`).
2. **Plan** — for near-term (task-level) WBS leaves lacking RDs yet, note that estimation here is provisional pending `/cz:rd`; for feature/epic-level WBS nodes in later waves, plan a rough three-point estimate at that granularity instead (no RD exists yet to roll up from).
3. **Delegate** — send `deliverables/WBS-$1.md` and the existing RD estimate fields to the `planner` agent via Task. Instruct it to roll up RD-level three-point estimates per WBS branch using standard PERT (`expected = (optimistic + 4*expected + pessimistic)/6` at the RD level, then sum expected values per branch, and propagate optimistic/pessimistic as min/max envelopes, not naive sums).
4. **Execute** — `planner` writes `deliverables/EST-$1.md`: a table per WBS branch with rolled-up optimistic/expected/pessimistic hours, a project total, and a confidence note flagging any branch where later-wave epic-level guesses dominate the total (i.e., where real RD data is still thin).
5. **Gate** — read `human_gates.estimate` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/EST-$1.md` to the human; on approval write `gate-records/PB5-estimate.json` with `{step:5, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 7's validity check is clean.
6. **Log** — append Delivery Log entry and a new Understanding Gate question, e.g. "Which branch's estimate are you least confident in, and why?" Requires a human-authored answer only when `human_gates.estimate` is `true`; otherwise logged for visibility.
7. **Iterate** — if any near-term RD estimate violates the RD validity rule (`expected_h <= 4` and `pessimistic_h <= 6`), it must be split via `/cz:rd` before it can be rolled up here; loop back to step 1 until clean.

Exit condition: `gate-records/PB5-estimate.json` passed. `deliverables/EST-$1.md` is re-run incrementally as later waves gain real RDs, not treated as a one-time snapshot.
