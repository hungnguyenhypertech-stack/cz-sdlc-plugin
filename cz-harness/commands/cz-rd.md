---
description: Decompose the current wave only into RDs, proposing splits per the six validity rules
argument-hint: [wbs-leaf-id]
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

Decomposes near-term-wave `WBS-*` leaves into RDs (`RD-<proj>-<nnn>.<mm>`, e.g. `RD-PB01-014.02`). This is **rolling-wave**: only the current wave's leaves get decomposed into RDs now; feature/epic-level nodes in later waves stay coarse until `/cz:wbs` promotes them at wave rollover.

An RD is valid only if **all six** hold — check every one, every time:
1. Exactly one observable behavior.
2. 1-3 acceptance criteria.
3. Independently testable (a TC could be written today with no missing fixture/data).
4. `estimate.expected_h <= 4` AND `estimate.pessimistic_h <= 6`.
5. Maps to exactly one module (per `deliverables/MODULEMAP-<proj>.md`).
6. No conjunction ("and"/"also"/"then also") hiding a second behavior in the RD statement — extra detail belongs in the AC, not bolted onto the statement with "and".

7-beat loop:

1. **Context** — load the WBS leaf `$1`, its parent module (from `deliverables/MODULEMAP-<proj>.md`), and `deliverables/ARCH-<proj>.md` for interface detail.
2. **Plan** — draft one or more candidate RDs for this leaf, each with a `summary` field: a single line (aim for under ~90 chars) glossing the statement in scannable form — this is what `board/board.html`'s RD table shows per row, so write it for someone skimming 25 RDs at a glance, not as a restatement of the full behavior.
3. **Delegate** — send the draft(s) to whichever agent owns this leaf's phase context (typically `planner` for first-pass drafting, or `test-designer`/`dev` if a split is discovered **mid-loop** during `/cz:build`). Any agent may **propose** a split.
4. **Execute** — automatic split is proposed (not applied) when any of: more than 3 AC; an AC spans two modules; the statement contains "and"/"also"/"then also" hiding a second behavior; `expected_h > 4` or `pessimistic_h > 6`; or an agent exhausted its context mid-loop while implementing/testing (a stall/thrash signal from `telemetry/events.jsonl`). Each proposed split becomes RD `<nnn>.01`, `<nnn>.02`, etc. under the same parent WBS leaf.
5. **Gate** — read `human_gates.rd_commit` from `config/gates.yaml` (**default `true`** — the only `human_gates` key defaulting on, per plan §4.1: "Splitting is proposed by agents and committed by the human. An agent that can silently redefine the work has escaped the delegation map."). If `true`: a human reviews every RD draft (and every proposed split) against the six rules and either commits it (writes to `rd/RD-<proj>-<nnn>.<mm>.md` with `content_hash` computed) or sends it back to step 2. If a project has deliberately set it `false` for an unattended run: the six rules are still re-checked programmatically before any write, but auto-commit under this setting **must** be made as visible as the Light red-skip exception (§8.4) — write `human_gates_bypassed: true` permanently onto the committed RD record, emit a governance event (`event: rd_auto_committed`), and surface the count on the board/RTM, so an unattended run can't quietly accumulate agent-defined scope with no trace. Any of the six rules failing sends the draft back to step 2 automatically rather than writing an invalid RD, regardless of this setting.
6. **Log** — append a Delivery Log entry to `deliverables/understanding-log/rd-commits.md` per committed RD batch (this is a phase-level fragment shared across all `/cz:rd` invocations, distinct from each committed RD's own `deliverables/understanding-log/rd/<rd-id>.md`, which `/cz:dor`/`/cz:gate` write to later).
7. **Iterate** — repeat for every current-wave leaf until none remain unRD'd; this command does not touch later-wave WBS nodes.

Exit condition: every current-wave WBS leaf has at least one committed, six-rule-valid RD under `rd/`. Each committed RD is then ready for `/cz:dor`.
