---
description: Phase 4 — build a rolling-wave WBS from the architecture
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

Phase 4 of the cz-harness playbook. Project code `$1`. Output artifact: `deliverables/WBS-$1.md`.

**Gate check**: refuse unless `gate-records/PB3-arch.json` is `status:"passed"`. Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/WBS-*.md` unless that gate record already shows `status:"passed"` on disk.

7-beat loop:

1. **Context** — load `deliverables/ARCH-$1.md` and `deliverables/MODULEMAP-$1.md`. Load `state/board.json` to see which wave is currently active (wave number tracked there).
2. **Plan** — this is a **rolling-wave** WBS, not a big-bang one. Decide wave boundaries: near-term wave = decomposed to task level (small enough to become RDs directly), next wave = feature level (bundles of tasks, not yet split into RDs), later waves = epic level (module-sized placeholders only).
3. **Delegate** — send `deliverables/ARCH-$1.md` to the `planner` agent via Task, explicit about wave granularity rules above and that layer-0 modules should generally land in earlier waves than the layer-1 modules that depend on them.
4. **Execute** — `planner` writes `deliverables/WBS-$1.md` as a tree: `WBS-$1-<nnn>` nodes tagged with `wave` (0=near-term, 1=next, 2+=later) and `granularity` (task|feature|epic) consistent with its wave. Near-term wave nodes are the leaves `/cz:rd` will decompose into RDs. If `deliverables/ARCH-$1.md` has a "Scaffolding" section (repo/test-runner setup not yet decided or not yet stood up — `agents/sa.md` Hard rule 6), `planner` MUST add a dedicated near-term-wave, task-granularity WBS leaf for it (repo scaffolding: package manifest + test-runner install/config), tagged `module: scaffolding` (the convention `commands/cz-build.md` step 1 checks for), ordered before every other near-term-wave leaf so `/cz:rd` turns it into the first RD any build loop depends on — not left implicit for whichever RD happens to reach `/cz:build` step 4 first.
5. **Gate** — read `human_gates.wbs` from `config/gates.yaml` (default `false`). If `true`: present `deliverables/WBS-$1.md` to the human; on approval write `gate-records/PB4-wbs.json` with `{step:4, status:"passed", approver, timestamp}`. If `false`: auto-write the same record with `approver:"auto"` once step 7's coverage check is clean.
6. **Log** — append Delivery Log entry and a new Understanding Gate question, e.g. "Why is feature Y in the next wave and not the near-term wave?" Requires a human-authored answer only when `human_gates.wbs` is `true`; otherwise logged for visibility.
7. **Iterate** — any `deliverables/ARCH-$1.md` module with no WBS coverage in any wave loops back to step 3. Re-running `/cz:wbs` later (e.g. at wave rollover) re-plans the *next* wave down to task level without re-litigating completed waves.

Exit condition: `gate-records/PB4-wbs.json` passed. Near-term-wave leaves feed `/cz:estimate` and, ultimately, `/cz:rd`'s "WBS leaf (current wave) with no RD" orphan check in `/cz:report`.
