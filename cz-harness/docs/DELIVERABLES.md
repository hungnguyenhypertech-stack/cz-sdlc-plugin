# Deliverables

Every document an agent produces — including review agents — is a **deliverable**:
a Markdown file under `deliverables/`, with a small YAML frontmatter block, that
auto-renders to a human-friendly HTML sibling the moment it's written. This doc
is the single source of truth for that system: where deliverables live, the
frontmatter convention, and how the HTML rendering works.

## Why

Two problems this closes:

1. **Reviewability.** Before this, agent output was scattered as loose
   root-level files (`SCOPE-PB0X.md`, `RISK-PB0X.md`, ...) plus `reviews/**`,
   `reviews/security/**` — no consistent place, no non-technical-friendly
   rendering. A PM had to open raw Markdown to review anything.
2. **Future agent-performance mining.** Every deliverable carries the same
   frontmatter shape (`agent`, `kind`, `rd`, `step`, `verdict` where
   applicable). That's what makes it possible to later ask questions like
   "which agent's verdicts get overturned most at human approval?" or "how
   often does ai-reviewer's `no-blocking-issues-found` actually hold up" —
   without redesigning the artifact format at that point. This is deliberately
   laid down now, before any such analysis exists, per the plan's own AI
   Literacy / Outcome Leadership pillars (see `PILLAR-MAP.md`).

## What lives under `deliverables/` (and what doesn't)

`deliverables/` holds **narrative documents** — the reports and write-ups a
human is meant to read. It does **not** hold machine state that already has
its own schema and is consumed by hooks, not by a human reading prose:
`rd/*.md`, `state/**`, `telemetry/events.jsonl`, `gate-records/*.json`,
`config/gates.yaml`, `delegation-map.yaml` all keep their existing paths,
untouched by this system.

| Deliverable | Written by | Path |
|---|---|---|
| Scope | ba | `deliverables/SCOPE-<proj>.md` |
| Spec | ba | `deliverables/SPEC-<proj>.md` |
| Module map | sa | `deliverables/MODULEMAP-<proj>.md` |
| Architecture / ADRs | sa | `deliverables/ARCH-<proj>.md`, `deliverables/adr/*.md` |
| Work breakdown | planner | `deliverables/WBS-<proj>.md` |
| Estimates | planner | `deliverables/EST-<proj>.md` |
| Risk register | risk-gov | `deliverables/RISK-<proj>.md` |
| Delegation map (narrative) | risk-gov | `deliverables/DELEGATION-MAP-<proj>.md` |
| Definition of Ready | test-designer | `deliverables/DOR-<rd-id>.md` |
| Coverage verification (step 9) | test-designer | `deliverables/coverage/<rd-id>.md` |
| Dev Book | dev | `deliverables/DEVBOOK-<rd-id>.md` |
| Gate 1 review | ai-reviewer | `deliverables/reviews/RD-<id>-gate1.md` |
| Gate 2 review | sec-reviewer | `deliverables/reviews/security/RD-<id>-gate2.md` |
| Traceability matrix | agentops | `deliverables/RTM-<proj>.md` |
| Weekly status | agentops | `deliverables/WEEKLY-<proj>.md` |
| Case study | agentops | `deliverables/CASE-STUDY-<proj>.md` |
| Health check (7-dimension memory-quality report) | agentops (via `/cz:health-check`, no gate) | `deliverables/HEALTH-CHECK-<proj>.md` |
| Plain-language explainer | ad hoc (via `/cz:explain`) | `deliverables/EXPLAIN-<rd-id>.md` (optional) |
| Delivery/Understanding log (phase-level) | init/scope/spec/rd/report/audit/rebuild-state/viva commands (append, own fragment only) | `deliverables/understanding-log/<phase>.md` (e.g. `init.md`, `scope.md`, `spec.md`, `rd-commits.md`, `report.md`, `audit.md`, `rebuild-state.md`, `viva.md`) |
| Delivery/Understanding log (per-RD) | test-designer (`/cz:dor`), ai-reviewer/human (`/cz:gate`) (append, own fragment only) | `deliverables/understanding-log/rd/<rd-id>.md` |

Every one of these paths is also what the writing agent's `tools:` allow-list
in `agents/*.md` grants — the least-privilege boundary just moved under
`deliverables/`, it didn't loosen. `reviews/**` and `reviews/security/**`
stayed literal folder names (just nested one level deeper) specifically so
`hooks/guard-role-boundaries.sh`'s existing `*/reviews/*` / `*/gate-records/*`
path checks keep working unmodified.

## Frontmatter convention

Every deliverable starts with:

```
---
kind: SCOPE | SPEC | MODULEMAP | ARCH | ADR | WBS | EST | RISK |
      DELEGATION-MAP | DOR | COVERAGE | DEVBOOK | REVIEW-GATE1 |
      REVIEW-GATE2 | RTM | WEEKLY | CASE-STUDY | EXPLAIN | HEALTH-CHECK
agent: ba | sa | planner | risk-gov | test-designer | dev |
       ai-reviewer | sec-reviewer | agentops
rd: <RD-ID> | null        # null for project-level docs (SCOPE, SPEC, RTM, ...)
step: <0-10 | n/a>
verdict: <block | needs-fixes | no-blocking-issues-found | pass | fail>  # review/gate kinds only
created_at: <RFC3339 timestamp>
---
```

This is a minimal top-level `key: value` block — the same "dependency-free
fallback" parsing philosophy as `cz_rd_field` in `hooks/lib/common.sh`, not a
full YAML parser. Keep it flat; don't nest.

## HTML rendering

`hooks/render-deliverable.sh` is a `PostToolUse` hook (matcher: `Write`,
`hooks/hooks.json`) that fires after every Write. If the write landed under
`deliverables/**/*.md`, it:

1. Refreshes `deliverables/_assets/style.css` from the plugin's canonical copy
   (`templates/deliverables/style.css`) — the one stylesheet every rendered
   page links to, so no agent or hook ever authors CSS/HTML from scratch and
   no tokens are spent generating markup.
2. Converts the Markdown (via the stdlib-only `hooks/lib/render_deliverable.py`)
   into a sibling `.html`, wrapped in `templates/deliverables/page.html.tmpl`,
   with badges built from the frontmatter.
3. Rebuilds `deliverables/index.html` — a single filterable table of every
   deliverable (by agent, RD, kind, verdict), linked from `board/board.html`.

This is **non-blocking by construction**: a render failure (bad Markdown,
missing python3, whatever) logs a warning and the underlying Write still
succeeds. It only makes output easier to read; it must never gate anything.

To review a deliverable: open its `.html` sibling, or start from
`deliverables/index.html` and filter. `/cz:board` links to it.

## Adding a new deliverable kind

1. Give the writing agent a `Write(deliverables/<pattern>)` entry in
   `agents/<agent>.md`'s `tools:` line.
2. Add a "Deliverable format" section to that agent file with the frontmatter
   block (copy an existing one, change `kind`/`agent`/`step`).
3. Add a row to the table above.
4. Nothing else — the render hook and index already scan `deliverables/**/*.md`
   generically; no per-kind code is needed.
