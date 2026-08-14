---
description: Score traceability memory (not just its graph shape) across 7 dimensions — coverage, change coupling, freshness, orphan rate, review evidence, decision coverage, retrieval quality
argument-hint: [project-code]
allowed-tools: Read, Write(deliverables/HEALTH-CHECK*.md), Write(deliverables/HEALTH-CHECK*.json), Bash, Grep, Glob, Task
---

Answers one question for project `$1`: **if we have a lot of documentation, is it correct, alive, and usable?** — the check that must follow any "we have full traceability" claim (see `docs/PILLAR-MAP.md`'s Governance pillar and `skills/traceability/SKILL.md`).

This is deliberately not `/cz:report`. `/cz:report` walks the **RTM's 7 orphan classes** (a graph-shape check: does every id resolve to another id) and refuses to run at all until at least one RD has an approved gate. `/cz:health-check` walks **7 memory-quality dimensions** and has no such gate — it is read-only, side-effect-light, and safe to run at any project stage, including day one, specifically so a PM can see how the traceability chain is actually holding up *before* deciding whether a full RTM run is worth it. Where the two overlap (both touch orphans), health-check's coverage/orphan checks are strictly the RTM's 7 classes **plus** the "lineage exhausted" case the RTM's static graph check cannot see: a REQ whose every RD is `withdrawn`/`superseded` with no live successor looks, to a pure graph walk, like "has RDs" — it only reveals itself as broken when you also check RD *state*, not just RD *existence*.

7-beat loop:

1. **Context** — load `deliverables/SPEC-$1.md` (or the project's REQ list), every `rd/RD-$1-*.md` (frontmatter: `state`, `parent_req`, `version`, `content_hash`, `notes`), `deliverables/MODULEMAP-$1.md`, `deliverables/ARCH-$1.md` (including any inline `#### ADR-NNN` sections — decisions are not guaranteed to live in `deliverables/adr/*.md` even when that's the nominal path), `deliverables/adr/*.md` if present, `src/**` and `tests/**` (grep for `RD-$1-*`/`AC-$1-*` id annotations), every `gate-records/*.json`, `deliverables/reviews/**`, `state/board.json`, and `telemetry/events.jsonl`.

2. **Plan** — compute each of the 7 dimensions as a concrete, countable check, not a vibe:
   - **Coverage** — for every REQ, find whether an `accepted`-state RD's `parent_req` covers it. Report `covered / total`. Separately list REQs whose *only* RD lineage is `draft` (legitimately in-flight — not a defect) vs. REQs whose *entire* RD lineage is `withdrawn`/`superseded` with no live successor (a real gap the RTM's orphan-class-1 check cannot see, since it only asks "does a RD exist", not "is any RD of it alive").
   - **Change coupling** — for each RD at `version >= 2`, read its `notes` change-log: does it state which fields changed and why `content_hash` did/didn't recompute (per the Freeze Rule in `skills/traceability/SKILL.md`)? Separately, diff every `deliverables/**/*.md` mtime against its rendered `.html` sibling's mtime (`hooks/render-deliverable.sh`'s output) — a `.md` newer than its `.html` means a write landed without the render hook firing, the same class of drift `ai-reviewer` caught by hand in at least one past gate-1 round-2 finding.
   - **Freshness** — grep `src/**` and `tests/**` for RD-id citations in comments, resolve each cited id's current `state` in `rd/*.md`. Flag any citation of a `withdrawn`/`superseded` id from a file that is otherwise live (not itself withdrawn) — a dead-end for anyone tracing test→RD.
   - **Orphan rate** — run the RTM's 7 orphan classes (`skills/traceability/SKILL.md` §"RTM Orphan Classes") read-only (do not block anything, this command has no gate), plus: every module in `deliverables/MODULEMAP-$1.md` has a corresponding section in `deliverables/ARCH-$1.md` (module orphan check).
   - **Review evidence** — across all `gate-records/*.json`: tally `ai_review.verdict` distribution (pass / needs-fixes / fail) and `gate_decision.approver` distribution (`auto` vs any non-`auto` value). An all-`auto` approver distribution is not itself a defect (it can be the correct outcome of `config/gates.yaml`'s `human_gates` being off for this profile) — report it as a fact plus what it implies (zero literal human sign-off trace) and cross-check whether that's consistent with the project's actual `human_gates` config, the same non-retroactive check `/cz:audit` already does for individual phases.
   - **Decision coverage** — for every module `RISK-$1.md`/`DELEGATION-MAP-$1.md` rates `hazard: high` (or any `hazard: true` RD), confirm a decision record exists explaining *why* — either a `deliverables/adr/*.md` file or a `#### ADR-NNN` section inside `deliverables/ARCH-$1.md`. Report which location holds each one found, since the two are not interchangeable for a reader who only looks in one place.
   - **Retrieval quality** — pick up to 5 REQ ids (weighted toward any flagged by Coverage/Orphan rate) and, for each, attempt a full-chain walk: REQ → RD → AC → TC/test file → gate-records → review report. Report which chains resolve end-to-end vs. where each broken one dead-ends (this is the same manual walk a human or an agent would have to do live if asked "where does REQ-N live" — the point of this dimension is measuring how many hops that takes today, not assuming it's fine because the ids exist somewhere).

3. **Delegate** — dispatch the `agentops` agent via Task with the raw per-dimension findings from step 2 (counts, id lists, mtime diffs, verdict tallies — not conclusions). Instruct it to write the narrative report, cite every finding back to its source file/line rather than asserting a number unsupported by a citation, and to keep the same "state a fact plus its implication, don't editorialize past the evidence" register `ai-reviewer`'s gate-1 reports already use.

4. **Execute** — `agentops` writes `deliverables/HEALTH-CHECK-$1.md`: a per-dimension section (Coverage, Change coupling, Freshness, Orphan rate, Review evidence, Decision coverage, Retrieval quality) each with its count/ratio, its concrete finding list, and one "next action" pointing at the command that would close the gap (e.g. a lineage-exhausted REQ → re-cut a fresh RD via `/cz:rd`; a stale doc render → re-run `render-deliverable.sh` or re-`Write` the file; an all-`auto` approver tally on a profile that expects human sign-off → escalate to the human, don't silently patch `config/gates.yaml`). No pass/fail gate verdict is produced — this command reports health, it does not block anything.
   In the same dispatch, `agentops` also writes `deliverables/HEALTH-CHECK-$1.json` — a machine-readable sidecar of the exact same findings, in the shape `board/board.html`'s `HEALTH_CHECK` object expects (see that file's schema comment above the `HEALTH_CHECK_EMPTY` constant):
   ```
   {
     "checked_at": "<RFC3339 timestamp>",
     "project": { "reqs": <int>, "rds": <int>, "modules": <int> },
     "diagnosis": "<optional html string>",
     "sources": ["<optional file/path>", ...],
     "dimensions": [
       { "key": "coverage", "name": "Coverage", "status": "clean"|"gap", "severity": "clean"|"gap"|"hot",
         "ratio": <0-100>, "metric": "<e.g. '9/10 REQs covered'>", "headline": "<one-line finding>",
         "findings": ["<html>", ...], "next": "<html next-action>" },
       ... one object per dimension, same 7 keys as the .md sections: coverage, change_coupling, freshness,
       orphan_rate, review_evidence, decision_coverage, retrieval_quality ...
     ],
     "nextActions": [ { "gap": "<short label>", "dim": "<dimension key>", "action": "<html>" }, ... ]
   }
   ```
   This is the one deliverable in this command with a JSON sidecar requirement — without it the board's Health Check tab has no live data source and stays on its "not run yet" empty state (`board/board.html`'s `refresh()` fetches `../deliverables/HEALTH-CHECK-<project>.json` every cycle, same pattern as `state/board.json`/`gate-records/index.json`, and falls back to empty on a 404 or parse error). No hand-transcription into `board.html` is needed or expected anymore.

5. **Gate** — none. This command never blocks a pipeline step and is not itself a pipeline step (`step: n/a` in its deliverable, same convention as `/cz:explain`'s `EXPLAIN` kind). Running it, or finding problems with it, has no effect on `state/board.json`.

6. **Log** — append a Delivery Log entry to `deliverables/understanding-log/health-check.md` summarizing the 7 scores/ratios. Add an Understanding Gate question only if a lineage-exhausted REQ (Coverage) or a `hazard:true` module with no decision record anywhere (Decision coverage) was found — e.g. "Which of these gaps would you actually fix first, and why that one before the others?" — since those two findings are judgment calls for the human, not mechanical facts like the rest.

7. **Iterate** — this command is idempotent and safe to re-run anytime (before/after `/cz:rd`, `/cz:build`, or `/cz:report`) to see whether a specific gap closed. It is a reasonable pre-flight before `/cz:report`: a `/cz:report` run on a `standard`/`heavy` profile will itself block on current-wave orphans, so running `/cz:health-check` first shows you the same orphans (plus the 3 extra dimensions RTM doesn't check) without tripping that block.

Exit condition: `deliverables/HEALTH-CHECK-$1.md` exists and states, per dimension, a number/ratio plus the specific findings behind it — never a bare "looks healthy" with no citation.
