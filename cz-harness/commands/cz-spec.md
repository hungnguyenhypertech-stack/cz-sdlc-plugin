---
description: Phase 1 — turn scope into numbered REQ-* requirements
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task, Bash(git log:*)
---

Phase 1 of the cz-harness playbook. Project code `$1`. Output artifact: `deliverables/SPEC-$1.md`, containing requirements `REQ-$1-<nnn>`.

**Gate check before starting**: refuse to run unless `gate-records/PB0-scope.json` has `status:"passed"`; additionally, if `human_gates.scope` in `config/gates.yaml` is `true`, also require a human-authored answer to the step-0 Understanding Gate question in `deliverables/understanding-log/scope.md`. If any required item is missing, print it and stop. The `status:"passed"` half of this check is mechanically enforced, not advisory — `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/SPEC-*.md` unless `gate-records/PB0-scope.json` already shows `status:"passed"` on disk, mirroring `guard-state-transition.sh`'s enforcement of the RD-level state machine.

7-beat loop:

1. **Context** — load `deliverables/SCOPE-$1.md`, the answered Understanding Gate entry, and any existing `deliverables/SPEC-$1.md` to avoid REQ-ID collisions.
2. **Plan** — enumerate candidate requirement clusters mapped 1:1 to the Goals section of `deliverables/SCOPE-$1.md`; flag any goal with no corresponding requirement draft.
3. **Delegate** — hand the scope doc and cluster plan to the `ba` agent via Task, instructing it to produce atomic, testable requirements — one observable capability per REQ, no "and/also" compound requirements (the same conjunction rule later enforced on RDs applies here in spirit).
4. **Execute** — `ba` writes `deliverables/SPEC-$1.md` with one row per requirement: `REQ-$1-001`, statement, priority (MoSCoW), source (which Goal/OQ it traces to), acceptance sketch (1-2 lines, refined later into RD-level AC).
5. **Gate** — read `human_gates.spec` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/SPEC-$1.md` to the human; on approval write `gate-records/PB1-spec.json` with `{step:1, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 4's output is complete and step 7's OQ check is clean.
6. **Log** — append Delivery Log entry to `deliverables/understanding-log/spec.md` plus a new Understanding Gate question, e.g. "Which REQ would you cut first if the timeline halved, and why?" Requires a human-authored answer only when `human_gates.spec` is `true`; otherwise logged for visibility.
7. **Iterate** — unresolved `OQ-$1-*` items from Phase 0 must be closed or explicitly deferred (recorded as a REQ note) before the gate can pass; otherwise loop back to step 3.

Exit condition: `gate-records/PB1-spec.json` passed. Every `REQ-$1-*` must trace back to a Goal in `deliverables/SCOPE-$1.md` — this traceability is what `/cz:report`'s RTM check later validates (orphan class: "REQ with no RD" is checked downstream, but "REQ with no source goal" is checked here).
