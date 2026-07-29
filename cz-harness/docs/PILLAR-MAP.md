# Pillar Map

CZ-Harness exists to make six AI-native PM capability pillars *enforced by tooling*, not
aspirational. This document is the canonical cross-reference: for each pillar, which artifact
carries the evidence, which mechanism makes the artifact non-optional, and which metric a PM
or lead can pull off the board to check whether the pillar is actually being exercised rather
than nominally present.

Read this file whenever you need to justify "why does the harness force me to do X" — the
answer is always "because pillar Y depends on it and there is no other place to catch it."

## The Map

> All named Markdown artifacts below (`understanding-log/**`, `DEVBOOK-PB0X.md`,
> `DELEGATION-MAP-PB0X.md`, `RISK-PB0X.md`, `RTM-PB0X.md`, `WEEKLY-PB0X.md`, `CASE-STUDY.md`)
> live under `deliverables/` and auto-render to HTML — see `docs/DELIVERABLES.md`. Only
> `config/delegation-map.yaml`, `gates.yaml`, `gate-records/*.json`, and `telemetry/events.jsonl`
> are machine state at their own top-level paths, unaffected by that system.

| Pillar | Artifact(s) | Enforcing Mechanism | Metric |
|---|---|---|---|
| **AI Literacy** | `understanding-log/**`, `DEVBOOK-PB0X.md` | Every phase command and every RD acceptance appends an Understanding Gate question that requires a human-authored answer (not AI-generated, not a checkbox). Dev Book requires ≥1 human correction per RD at Standard profile and above — a correction is a substantive edit to AI-produced content, not a typo fix. | Understanding Gates answered ÷ RDs accepted; corrections logged per RD |
| **AI Delegation** | `DELEGATION-MAP-PB0X.md`, `config/delegation-map.yaml` | Every RD carries an explicit delegation level (L0–L5) plus a leash designation (A / A+). An RD with no delegation record cannot be claimed by any agent — the claim hook checks the map before allowing a state transition into `in_progress`. | % of RDs with an explicit level recorded; count of L4 grants; count of escalation events |
| **Workflow Design** | `rd/*.md` registry, `state/board.json` | Two state machines (RD lifecycle, gate lifecycle) are enforced at the hook layer, not caught in review. An illegal transition (e.g., `red` → `merged` without a passing gate) is rejected by the hook before it ever reaches a human reviewer. | RD cycle time by state; time-in-state; stall count (RDs idle > N hours in a non-terminal state) |
| **Governance & Risk** | `RISK-PB0X.md`, `gates.yaml`, `gate-records/*.json` | Fail-closed gate engine: AI review → security review → human approval, in that order, with no skip path except the documented `red_skipped` exception (Light profile only). Secrets deny-list blocks writes containing credential patterns. No self-merge (the agent that authored a change cannot be the approving identity). Hard-stop halts the RD on detected contradiction between artifacts. | Gate blocks (count, by stage); hazard escalations; hard-stops raised/closed; `red_skipped` count |
| **Telemetry & Economics** | `telemetry/events.jsonl` | Hooks append one event per tool call, per test run, per gate decision, and per approval. Every event is tagged with an RD id — untagged events fail schema validation and are quarantined rather than silently dropped. | Cost per RD; compression ratio (context sent vs. context needed); token reconciliation delta (estimated vs. actual spend) |
| **Outcome Leadership** | `RTM-PB0X.md`, live board, `WEEKLY-PB0X.md`, `CASE-STUDY.md` | RTM and weekly reports are generated *from the registry*, never hand-assembled. The generator refuses to run if it finds orphan links or unreconciled telemetry at Standard profile or above — a red exit code, not a warning. | Rework rate; estimation accuracy per RD (expected vs. actual hours); ROI; rubber-stamp risk score |

## Rubber-Stamp Risk (Advisory Signal)

`rubber_stamp_risk` is a composite, advisory signal — it estimates the likelihood that a human
"approval" was a rubber stamp rather than a genuine review. It is **not surveillance**: the
score is computed for the participant's own awareness first, surfaced to them before it is
surfaced to anyone above them, and it is explicitly not used as a performance metric by default.
The intent is to give a PM a mirror, not a leash.

```
rubber_stamp_risk = f(
  human_review_minutes_per_1k_ai_output_tokens,   # lower = faster than plausible reading speed
  corrections_logged_per_RD,                       # near-zero across many RDs is a signal
  gate_pass_on_first_attempt_rate,                 # suspiciously high across all RDs
  seconds_between(artifact_ready, human_approval)  # near-instant approval on non-trivial artifacts
)
```

None of the four inputs is damning alone (a trivial RD legitimately reviews fast and passes
first try). The signal is meant to be read as a trend across many RDs by the same approver, and
it is always shown to that approver before it appears on any aggregate view. Treat a high score
as "worth a conversation," not "proof of negligence."

## CZ-Harness Extensions Beyond the Base Playbook

Two mechanisms in this harness go beyond what the base CASAN-aligned playbook strictly
requires. They are called out here so that anyone auditing against the playbook understands
these are intentional tightenings, not misreadings:

1. **Per-RD Understanding Gate.** The base playbook only requires gates at the *step* level
   (phase-command granularity). CZ-Harness additionally requires an Understanding Gate question
   at RD-acceptance granularity — i.e., on every single RD, not just at phase boundaries. This
   is a deliberate extension to keep AI literacy from decaying on long RD registries where
   phase-level gates might be minutes apart in wall-clock time but hours apart in RD count.

2. **Per-RD Dev Book correction floor.** The base playbook asks for Dev Book evidence "per
   meaningful build step" — a qualitative, judgment-based bar. CZ-Harness converts this into a
   tallied minimum: ≥1 human correction logged per RD at Standard profile and above. This is
   stricter and more mechanical than the playbook's language, traded deliberately for
   auditability over flexibility.

Both extensions can be relaxed by choosing Light profile (see `LIGHTWEIGHT-MODE.md`), but the
relaxation is itself logged, never silent.
