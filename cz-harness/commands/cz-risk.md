---
description: Phase 6 — assess risk and set the agent-delegation ceiling per module/RD
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

Phase 6 of the cz-harness playbook. Project code `$1`. Output artifacts: `deliverables/RISK-$1.md` and `deliverables/DELEGATION-MAP-$1.md`.

**Gate check**: refuse unless `gate-records/PB5-estimate.json` is `status:"passed"`. Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/RISK-*.md` or `deliverables/DELEGATION-MAP-*.md` unless that gate record already shows `status:"passed"` on disk.

7-beat loop:

1. **Context** — load `deliverables/ARCH-$1.md`, `deliverables/MODULEMAP-$1.md`, and `deliverables/EST-$1.md`. Identify modules touching auth, payments, PII, external network egress, or irreversible operations as candidate hazard areas.
2. **Plan** — for every module, sketch a hazard rating (low/med/high) and a leash rating (A = standard leash, agent proceeds through normal gates with human checkpoints at defined gate points only; A+ = tightened leash for hazard/security-sensitive modules, additional human checkpoint(s) beyond standard and a mandatory `sec-reviewer` pass at gate 2) based on hazard, blast radius, and reversibility.
3. **Delegate** — send `deliverables/ARCH-$1.md`, `deliverables/MODULEMAP-$1.md`, and the draft ratings to the `risk-gov` agent via Task. Instruct it to justify each hazard/leash pair in one sentence and to resolve any module rated hazard=high with leash=A (a contradiction) itself before writing the deliverable — either by tightening the leash or lowering the hazard justification.
4. **Execute** — `risk-gov` writes `deliverables/RISK-$1.md` (per-module hazard, leash, top risks, mitigations, and a flag for any module where hazard=high or leash=A+ — since those require a mandatory `sec-reviewer` pass at gate 2) and `deliverables/DELEGATION-MAP-$1.md` (per-module: which agent roles proceed under the standard leash A vs. which require the tightened leash A+, derived directly from the leash rating).
5. **Gate** — read `human_gates.risk` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/RISK-$1.md`/`deliverables/DELEGATION-MAP-$1.md` to the human (risk-gov's output is itself a governance artifact, not separately AI/security-reviewed at this phase); on approval write `gate-records/PB6-risk.json` with `{step:6, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 7's pairing check is clean and no unresolved hazard=high/leash=A contradiction remains.
6. **Log** — append Delivery Log entry and a new Understanding Gate question, e.g. "Which module's leash rating would you tighten if we found a security bug in production tomorrow, and why?" Requires a human-authored answer only when `human_gates.risk` is `true`; otherwise logged for visibility.
7. **Iterate** — any module missing a hazard/leash pair loops back to step 3.

Exit condition: `gate-records/PB6-risk.json` passed. `deliverables/RISK-$1.md`'s hazard/leash values are what `/cz:gate` reads to decide whether a security review is mandatory (hazard=high or leash=A+ triggers it).
