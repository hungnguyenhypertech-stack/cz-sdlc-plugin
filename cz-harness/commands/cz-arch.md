---
description: Phase 3 — design system architecture across the module map
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

Phase 3 of the cz-harness playbook. Project code `$1`. Output artifact: `deliverables/ARCH-$1.md`.

**Gate check**: refuse unless `gate-records/PB2-modulemap.json` is `status:"passed"`. Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/ARCH-*.md` unless that gate record already shows `status:"passed"` on disk.

7-beat loop:

1. **Context** — load `deliverables/MODULEMAP-$1.md`, sorting modules by `layer` (0 before 1) since foundation modules must be architected first — surface modules will reference their interfaces.
2. **Plan** — for each layer-0 module, plan its data model, external interfaces, and invariants; for each layer-1 module, plan how it consumes layer-0 interfaces without reaching around them.
3. **Delegate** — send `deliverables/MODULEMAP-$1.md` and `deliverables/SPEC-$1.md` to the `sa` agent via Task, layer 0 first. Instruct it to produce interface contracts (not implementations), call out cross-module dependencies explicitly, and flag any layer-1 module that appears to need a new foundation capability (kicked back to `/cz:modulemap` conceptually, not silently added here).
4. **Execute** — `sa` writes `deliverables/ARCH-$1.md`: one section per module (component responsibilities, data shapes, interfaces exposed/consumed, key architectural decisions with rationale, and non-functional constraints such as latency/security posture that later feed `/cz:risk`'s hazard/leash scoring). If the project has no repo scaffolding yet (no package manifest / test runner on disk) and any ADR here narrows the tech stack, `sa` must add an explicit "Scaffolding" section naming the still-open test-runner/tooling choice so `/cz:wbs` can plan it as its own work item — see `agents/sa.md` Hard rule 6. `/cz:build` step 4 (red proof) cannot run without a decided runner, so this cannot be left implicit.
5. **Gate** — read `human_gates.arch` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/ARCH-$1.md` to the human (a security-flavored ARCH concern still gets logged as a risk item for `/cz:risk`, not reviewed here); on approval write `gate-records/PB3-arch.json` with `{step:3, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 7's coverage check is clean.
6. **Log** — append Delivery Log entry and a new Understanding Gate question, e.g. "If module X's interface changed shape tomorrow, which modules break and why?" Requires a human-authored answer only when `human_gates.arch` is `true`; otherwise logged for visibility.
7. **Iterate** — any REQ from `deliverables/SPEC-$1.md` with no architectural coverage loops back to step 3.

Exit condition: `gate-records/PB3-arch.json` passed. `deliverables/ARCH-$1.md` is the reference `/cz:wbs` decomposes into work packages and `/cz:rd` later decomposes into RDs.
