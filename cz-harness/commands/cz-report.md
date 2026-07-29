---
description: Phase 10 — build the RTM, roll up telemetry, and produce weekly/case-study artifacts
argument-hint: [project-code]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task
---

Phase 10 of the cz-harness playbook. Project code `$1`. Outputs: `deliverables/RTM-$1.md`, telemetry rollups, `deliverables/WEEKLY-$1.md`, `deliverables/CASE-STUDY.md`.

**Gate check**: refuse unless at least one RD has a passed `gate-records/<rd-id>-gate.json` this reporting period (no report on zero delivered RDs). Mechanically enforced: `hooks/guard-pipeline-order.sh` (PreToolUse) blocks any write to `deliverables/RTM-*.md`, `deliverables/WEEKLY-*.md`, or `deliverables/CASE-STUDY.md` unless at least one `gate-records/*-gate.json` anywhere in the project already has `gate_decision.decision:"approved"` — project-wide, not tied to one RD id.

7-beat loop:

1. **Context** — load `deliverables/SPEC-$1.md`, all `rd/RD-$1-*.md`, `tests/**` TCs, `state/board.json`, `telemetry/events.jsonl`, and every `gate-records/*.json` for `$1`.
2. **Plan** — before writing anything, run the RTM orphan scan. Check all seven orphan classes:
   - REQ with no RD; RD with no `parent_req`; RD with no AC; AC with no TC; TC with no AC; RD with no WBS leaf; WBS leaf (current wave only) with no RD.
   Also count: stale TC count (per `guard-rd-freeze` flags), `red_skipped` count (RDs where no valid red log preceded green, if any slipped through), and `src/**` files with no RD-ID annotation.
3. **Delegate** — dispatch the `agentops` agent via Task with the full orphan scan results and raw telemetry. Instruct it to build the RTM table (`REQ -> RD -> AC -> TC -> gate status`), roll up cycle time / red-green loop counts / stall counts from `telemetry/events.jsonl`, and draft the weekly narrative and case-study update.
4. **Execute** — `agentops` writes `deliverables/RTM-$1.md` (full traceability table + orphan summary), a telemetry rollup (throughput, mean red-to-green time, stall count, gate pass/fail rate), `deliverables/WEEKLY-$1.md` (narrative for stakeholders), and appends to `deliverables/CASE-STUDY.md` (durable record across weeks, not overwritten).
5. **Profile gate** — check the active gate profile in `state/board.json` (`light`/`standard`/`heavy`, set by `/cz:init`):
   - `standard` or `heavy`: if any orphan in the seven classes exists **in the current wave**, **block** — do not emit `deliverables/WEEKLY-$1.md`; instead write a blocking report explaining which orphans must be resolved first.
   - `light`: emit `deliverables/WEEKLY-$1.md` anyway, but prepend a warning banner listing the current-wave orphans found.
6. **Log** — append a Delivery Log entry to `deliverables/understanding-log/report.md` summarizing what was reported/blocked, and a new Understanding Gate question, e.g. "Which orphan (if any) worries you most and why?" Requires a human-authored answer only when `human_gates.report` in `config/gates.yaml` is `true` (default `false`); otherwise logged for visibility.
7. **Iterate** — a blocked report (standard/heavy) is not a failure state to retry blindly — the specific orphan must be resolved (e.g. run `/cz:rd` to backfill a missing RD, or `/cz:wbs` for an uncovered leaf) and `/cz:report $1` re-run.

Exit condition: either a clean `deliverables/WEEKLY-$1.md` (no current-wave orphans, or `light` profile with warnings surfaced), or an explicit blocking report under `standard`/`heavy` that must be acted on before re-running.
