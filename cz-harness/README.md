# cz-harness

**An AI-native delivery Harness for FPT project managers.** RD-driven, fully traceable, real-time observable.

Built from `CZ-HARNESS-PLAN-v0.4.md` (2026-07-27). This is the Phase 0-5 scaffold per the plan's own build-phase table (§12): contracts, agents, commands, hooks, gate engine config, live board, and docs are all present; OmniRoute wiring (Phase 6) and a dogfood run against a real PB-0X brief (Phase 7) are not.

## What's here

| Path | What |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `agents/` | 10 role subagents (`sub-pm`, `ba`, `sa`, `planner`, `risk-gov`, `test-designer`, `dev`, `ai-reviewer`, `sec-reviewer`, `agentops`), each with a least-privilege tool allow-list |
| `commands/` | 19 slash commands — 11 map to the delivery pipeline's steps 0-10, 8 are cross-cutting (`/cz:rd`, `/cz:status`, `/cz:board`, `/cz:audit`, `/cz:explain`, `/cz:rebuild-state`, `/cz:viva`, `/cz:init`) |
| `hooks/` | 9 enforcing hooks — the load-bearing part. `guard-red-before-green.sh` and `guard-rd-freeze.sh` make strict SDD non-optional; `guard-state-transition.sh` is the RD state machine's sole authority; `guard-role-boundaries.sh` enforces the anti-collusion invariants; `guard-claim-lock.sh` gives one-RD-one-lock with lazy TTL reclaim; `detect-hazard.sh` escalates on the actual diff, not the declared module; `guard-secrets.sh` is the deny-list; `emit-telemetry.sh` + `project-state.sh` are the event-sourcing pipeline behind the board |
| `skills/` | 7 packaged skills (`rd-decomposition`, `sdd-loop`, `gate-engine`, `traceability`, `telemetry`, `devbook`, `viva-prep`), each a self-sufficient `SKILL.md` repackaging the same mechanics as the corresponding commands/docs for direct invocation by name |
| `config/` | `gates.yaml` (profile/concurrency/hazard config), `delegation-map.yaml`, `model-routing.yaml`, `hazard-paths.yaml`, `id-scheme.yaml` |
| `schemas/` | JSON Schemas for the RD record, test case, telemetry event, gate record, and board state — all validated against representative instances (see Verification below) |
| `templates/` | The 12 playbook artifacts + `UNDERSTANDING-LOG.md` + `CASE-STUDY.md` + RD/TC/gate-record/Dev-Book-entry templates, using the plan's own nightly-refresh / source-reconciliation worked example throughout. `templates/deliverables/` holds the shared `style.css` + `page.html.tmpl` every rendered deliverable reuses |
| `board/board.html` | Single-file, self-refreshing (~3s) live board — Workflow, Live board, Deliverables (RD priority/complexity/estimate-vs-actual/finished-date, plus deliverable/gate-review chips per RD), and Audit & Outcomes tabs. Reads `../state/board.json`, `../deliverables/index.json`, `../gate-records/index.json`. Stalls are computed client-side from heartbeat age — no hook ever writes a stall event |
| `board/build-audit-index.py` | Builds `gate-records/index.json` (audit trail + outcome metrics) that the Deliverables and Audit & Outcomes tabs read — including each RD's `estimate_variance` (see `hooks/compute-estimate-variance.sh`). Re-run after `gate-records/` or `telemetry/events.jsonl` change; not on an auto-write hook |
| `docs/` | `DELIVERABLES.md`, `PILLAR-MAP.md`, `CASAN-MAPPING.md`, `RD-GUIDE.md`, `TRACEABILITY.md`, `OPERATOR-GUIDE.md`, `LIGHTWEIGHT-MODE.md`, `SECURITY-NOTES.md` |

## Deliverables: every agent output is reviewable, in HTML

Every narrative document an agent writes (SCOPE, SPEC, ARCH, RISK, both gate reviews, RTM/WEEKLY/CASE-STUDY, ...) is a **deliverable**: it lives under the project's `deliverables/` tree with a small YAML frontmatter block, and `hooks/render-deliverable.sh` auto-renders it to an HTML sibling (shared stylesheet, zero per-deliverable authoring) the moment it's written, plus keeps `deliverables/index.html` current as a filterable cross-agent view. This is what makes agent output human-friendly to review today, and — because every deliverable carries the same `agent`/`kind`/`rd`/`step`/`verdict` frontmatter — is the substrate for evaluating agent performance later. See `docs/DELIVERABLES.md` for the full convention.

## Per-project runtime (not in this plugin)

Installing this plugin into a project does **not** create `rd/*.md`, `tests/**`, `evidence/`, `gate-records/`, `deliverables/`, `telemetry/events.jsonl`, or `state/` — those live in the *project* repo and are scaffolded by `/cz:init`.

## Test runner decision

The red/green hooks target **pytest** (`hooks/lib/test-runner-adapter.sh`), per the 2026-07-27 decision closing plan §14 open question 1. Other runners (vitest/jest, go test) are adapters in the same file — swap `CZ_TEST_RUNNER`.

## Verification performed on this build

- Every `.sh` file passes `bash -n` (syntax-checked).
- Every `.json` and `.yaml`/`.yml` file parses.
- `rd-template.yaml`, `tc-template.yaml`, and `gate-record-template.json` (comment-stripped) validate against their respective JSON Schemas.
- A sample `state/board.json` matching the plan's §7.2 mockup (52 total, all eight RD states reconciling) validates against `schemas/board-state.schema.json`.

## Not yet done (honest gap, matches plan §13/§14)

- Not wired into a real Claude Code runtime or exercised against a live agent session — hooks are unit-checked for syntax/schema, not integration-tested against actual tool-call interception (plan's own Phase-3 risk: "Claude Code hooks may not intercept every write path").
- OmniRoute adapter left at `adapter: direct` (Phase 6, deferred by design).
- No dogfood run (Phase 7) — this build has never produced a real Customer Zero.
- Plan §14 open questions 3-6 (FPT RD-template alignment, project code convention, language, repo home) remain open; `PB0X`/`PB04` placeholders are used throughout and are a project-wide find/replace away from a real project.
