---
description: Phase 0 — capture project scope and boundaries before any spec work
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Grep, Glob, Task, Bash(git log:*), Bash(git status:*)
---

Phase 0 of the cz-harness playbook. Project code is `$1` (e.g. `PB01`). Output artifact: `deliverables/SCOPE-$1.md` (see `docs/DELIVERABLES.md` for the layout; it auto-renders to `deliverables/SCOPE-$1.html`).

Run the 7-beat loop:

1. **Context** — read `state/board.json`, `deliverables/understanding-log/scope.md`, and any prior `deliverables/SCOPE-*.md` for this project. If `deliverables/SCOPE-$1.md` already exists with a passed gate record in `gate-records/`, refuse and tell the user to use `/cz:rd` or move to `/cz:spec` instead — this command does not overwrite a gated scope.
2. **Plan** — draft a scope outline: problem statement, in-scope capabilities, explicit out-of-scope list, stakeholders, success metrics, constraints (time/budget/compliance), and known unknowns.
3. **Delegate** — dispatch to the `ba` agent via Task with the draft outline and any source docs (briefs, transcripts, prior tickets) found under the project folder. Instruct the `ba` agent to interview the material, not invent scope.
4. **Execute** — `ba` writes `deliverables/SCOPE-$1.md` containing: Problem, Goals, Non-Goals, Stakeholders, Constraints, Assumptions, Open Questions. Every open question must be tagged `OQ-$1-<nnn>`.
5. **Gate** — read `human_gates.scope` from `config/gates.yaml` (default `true` if absent). If `true`: present `deliverables/SCOPE-$1.md` to the human; on approval write `gate-records/PB0-scope.json` with `{step:0, status:"passed", approver, timestamp}` (no AI/security review at Phase 0 either way). If `false`: auto-write `gate-records/PB0-scope.json` with `{step:0, status:"passed", approver:"auto", timestamp}` once step 4's output is complete.
6. **Log** — append an entry to `deliverables/understanding-log/scope.md`:
   - a **Delivery Log** line (what was produced, by whom, gate result)
   - an **Understanding Gate** question (e.g. "In one sentence, what will this project NOT do?"). If `human_gates.scope` is `true`, the answer must be human-authored, not copy-pasted from `deliverables/SCOPE-$1.md`, and is required before the exit condition is met. If `false`, the question is logged for visibility only and no answer is required.
7. **Iterate** — if the human rejects (only possible when `human_gates.scope` is `true`), return to step 2 with their feedback; do not advance.

Exit condition: `gate-records/PB0-scope.json` has `status:"passed"`, AND — only when `human_gates.scope` is `true` — the Understanding Gate question for step 0 has a human-authored answer in `deliverables/understanding-log/scope.md`. Only then may `/cz:spec` run.
