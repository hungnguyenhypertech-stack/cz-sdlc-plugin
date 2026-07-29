---
description: Phase 2 — partition REQ-* into modules and assign foundation/surface layers
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

Phase 2 of the cz-harness playbook. Project code `$1`. Output artifact: `deliverables/MODULEMAP-$1.md`.

**Gate check**: refuse unless `gate-records/PB1-spec.json` is `status:"passed"`. Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/MODULEMAP-*.md` unless that gate record already shows `status:"passed"` on disk.

7-beat loop:

1. **Context** — load `deliverables/SPEC-$1.md` in full; every `REQ-$1-*` must end up assigned to exactly one module.
2. **Plan** — sketch a candidate module list (e.g. `auth`, `billing`, `ingest-pipeline`) and, for each, whether it is `layer: 0` (foundation — no dependency on other in-project modules, e.g. data model, auth, shared config) or `layer: 1` (surface — depends on at least one foundation module, e.g. UI, reporting, integrations).
3. **Delegate** — send the REQ list and draft module list to the `sa` agent via Task. Instruct it to resolve ambiguous REQs (spanning candidate modules) by either tightening the module boundary or splitting the REQ, and to justify every `layer` assignment in one sentence.
4. **Execute** — `sa` writes `deliverables/MODULEMAP-$1.md` as a table: `module`, `layer` (0|1), `depends_on` (other module names, foundation modules should have an empty list), `owns_REQs` (list of REQ IDs). Flag any REQ assigned to more than one module as a spec-splitting defect and kick it back conceptually to `/cz:spec` (do not silently fix specs from this command).
5. **Gate** — read `human_gates.modulemap` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/MODULEMAP-$1.md` to the human; on approval write `gate-records/PB2-modulemap.json` with `{step:2, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 7's iteration check is clean.
6. **Log** — append Delivery Log entry and a new Understanding Gate question, e.g. "Why is module X layer 0 and module Y layer 1 — what breaks if we reversed it?" Requires a human-authored answer only when `human_gates.modulemap` is `true`; otherwise logged for visibility.
7. **Iterate** — if any REQ is unassigned or dual-assigned, loop back to step 3 before gating.

Exit condition: `gate-records/PB2-modulemap.json` passed. `deliverables/MODULEMAP-$1.md`'s `layer` column is the single source of truth `/cz:arch` and later RD validation ("maps to exactly one module") depend on.
