# CASAN Mapping

> Pinned to CASAN v1.0 (effective 2026-05-19). Re-sync cadence: every 6 months, or immediately
> on a published CASAN point-release that touches layers 3–5. If this document and the live
> CASAN spec disagree, the live spec wins and this file is stale until updated.

This document maps CZ-Harness's concrete implementation onto CASAN's 5-layer reference
architecture and 7 Harness components, and states the maturity level CZ-Harness targets out of
the box versus what it can honestly claim only after real operating history.

## 5-Layer Reference Architecture

| CASAN Layer | CZ-Harness Implementation |
|---|---|
| **Tầng 1 — Data** | RD registry (`rd/*.md`), traceability graph (derived from REQ/RD/AC/TC/WBS ids, see `TRACEABILITY.md`), golden test dataset (fixture corpus used by test-designer for regression baselining), telemetry store (`telemetry/events.jsonl`), artifact repo (generated docs, code, test logs under version control) |
| **Tầng 2 — Model** | Not applicable — OmniRoute reference adapter removed in 1.0.26 (see `SECURITY-NOTES.md`). Model selection per role is now just the static `model:` field in each `agents/*.md`; no gateway/adapter layer exists. |
| **Tầng 3 — Agent & Tools** | 10 role subagents (sub-pm, ba, sa, test-designer, dev, ai-reviewer, security-reviewer, risk-gov, telemetry-analyst, doc-writer — see role docs), each with a least-privilege tool allow-list; an MCP tool registry that declares which tools each role may invoke, enforced at dispatch time rather than by agent self-restraint |
| **Tầng 4 — Orchestration & Harness** | Sub-pm orchestrator (claims/assigns RDs, sequences phases); RD scheduler (respects concurrency bound, dependency edges between RDs); two state machines (RD lifecycle, gate lifecycle); SDD (spec-driven development) inner loop — write failing test (red) → implement → pass (green) → review, per RD |
| **Tầng 5 — Governance / Security / UX** | Gate engine (fail-closed, staged AI review → security review → human approval); approval records (`gate-records/*.json`); immutable audit log (append-only `telemetry/events.jsonl`, no update/delete path); hazard detector (path-based auto-escalation, see `SECURITY-NOTES.md`); live board (`state/board.json` rendered via `/cz:board`); slash-command UX (`/cz:init`, `/cz:board`, `/cz:status`, `/cz:explain`, `/cz:audit`, `/cz:rebuild-state`, and the 11 phase commands) |

## 7 Harness Components

CASAN evaluates a harness against 7 components. Status in CZ-Harness v1.0:

| Component (VN / EN) | Status | Notes |
|---|---|---|
| Ngữ cảnh / Context | Present | RD registry + traceability graph give every agent call a bounded, scoped context window per RD rather than whole-repo context |
| Công cụ / Tool | Present | MCP tool registry with per-role allow-lists; no role has blanket tool access |
| Kiểm định / Validation | Present | SDD inner loop (red→green) plus AI review stage; test freshness tracked via `content_hash` (see `TRACEABILITY.md`) |
| Bảo mật / Security | Present | Secrets deny-list, hazard-path auto-escalation, security-reviewer stage in the gate pipeline. (OmniRoute lockdown — not applicable, removed in 1.0.26, see `SECURITY-NOTES.md`) |
| Quản trị / Governance | Present | Fail-closed gate engine, no self-merge, hard-stop mechanism, human-only approval authority |
| AgentOps | **Partial** | Cost/telemetry tracking present. **Hallucination-rate detection and drift detection are explicitly DEFERRED** — not implemented in v1.0, not silently assumed. Flagged here so no one mistakes "telemetry exists" for "hallucination monitoring exists." |
| Điều phối / Orchestration | Present | Sub-pm orchestrator, RD scheduler, concurrency bounding by profile |

The AgentOps gap is intentional scope-cutting for v1.0, not an oversight. Any claim that
CZ-Harness "monitors for hallucination" or "detects drift" is false until this line item is
revisited in a future release.

## CASAN Maturity Target

CZ-Harness ships targeting **Cấp 3 (Standard)** maturity out of the box. This is a claim about
what the harness's mechanisms make *possible on day one*, not a claim about a specific
project's demonstrated track record.

- **Cấp 3 (Standard):** claimable at ship time. The gate engine, traceability, and telemetry
  mechanisms described above are sufficient to run a Standard-maturity delivery process from
  the first RD.
- **Cấp 4:** requires real operating history — a track record of gate pass rates, estimation
  accuracy, and rework rates accumulated over actual delivery, not a configuration setting.
  Cấp 4 is claimable *after* sustained use produces that evidence trail, never at ship. Do not
  represent a freshly-installed CZ-Harness project as Cấp 4.
- **Cấp 5:** out of scope for this harness entirely. No component here is designed to satisfy
  Cấp 5 requirements.

## A Note on Delegation Level L5

This harness imposes L5 (full autonomous delegation, no human in the loop) as a **hard
ceiling that must not be used** — this is a CZ-Harness policy choice, not a CASAN
restriction. CASAN itself, per §12.5, treats L5 as a real and legitimate delegation level
for narrow, high-control use cases such as fraud or compliance monitoring, provided it runs
under strict, independently audited control.

CZ-Harness's `delegation-map.yaml` schema supports L0–L5 structurally, but the harness's
default policy and its bundled agents refuse to grant L5 out of the box. If a project ever
needs to target CASAN Cấp 5 governance (e.g., a delivery team adopting full CASAN
governance), the L5 ceiling should be revisited against CASAN §12.5 rather than assumed to
still apply — it may be appropriate to allow L5 under the same strict-control conditions
CASAN describes.
