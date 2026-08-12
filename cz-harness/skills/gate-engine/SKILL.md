---
name: gate-engine
description: Run or reason about cz-harness's fixed-order review gate for a single RD (AI review, then security review if flagged, then human approval). Invoke when executing /cz:gate, when deciding whether security review is required for an RD, when explaining a gate-records/*.json outcome, or when comparing what Light/Standard/Heavy profiles actually require at each gate element.
---

# Gate Engine

Every RD that reaches `green` must pass through the same fixed sequence before it can be
`accepted`: AI review, then security review (conditionally), then human approval. This skill
packages plan §8.4 ("The gate engine"), `commands/cz-gate.md`'s exact step sequence, and
`config/gates.yaml`'s profile matrix so the ordering and profile trade-offs can be applied or
explained directly.

## When to use this skill

- Executing `/cz:gate <rd-id>` (Phase 9) — this skill IS that command's mechanics, spelled out.
- Deciding whether an RD needs `sec-reviewer` before it can be approved.
- Explaining a `gate-records/*.json` entry, or why a gate decision took the shape it did.
- Comparing what changes (and what never changes) across Light/Standard/Heavy profiles.

## The fixed order (not configurable)

```
RD green → [AI review] → [security review, conditional] → [human approval] → accepted
```

An artifact never reaches a human before an AI reviewer has had a pass — that keeps human
review time on judgment instead of typos, and is what makes the Light profile safe enough to
be worth having.

**Which profile applies to this RD**: since 1.0.26, check the RD's own `profile:` field
(`rd-template.yaml`, `schemas/rd.schema.json`) first — it overrides the module/project profile
downward for that one RD (set by `ba`/`planner` at `/cz:rd` time per the complexity heuristic in
`skills/rd-decomposition/SKILL.md`). Fall back to the module/project `config/gates.yaml` profile
only when the RD has no `profile:` field of its own. `hooks/lib/common.sh`'s
`cz_effective_profile` implements this same precedence for the mechanically-enforced hooks —
match it rather than reading `config/gates.yaml`'s `profile:` in isolation. AI review and, where triggered, security review **always** run and are always
recorded in `gate-records/*.json`, regardless of any `human_gates` setting; `human_gates` only
controls the approval step downstream of them.

## The `/cz:gate $1` step sequence

**Precondition**: refuse unless `deliverables/DEVBOOK-<rd-id>.md` exists and its green run is
byte-identical to its red run per `/cz:build`'s record.

1. **Context** — load DEVBOOK, red/green logs, the diff of touched `src/**` files, and the RD's
   module entry in `RISK-<proj>.md` (hazard + leash rating).
2. **Plan** — decide whether security review is required: triggered if the module's hazard
   rating is `high` or its leash rating is `A+` (tightened leash — hazard / heavy-profile
   oversight), per RISK/DELEGATION-MAP. Record this decision explicitly in the gate record
   before proceeding.
3. **Claim + state transition (before AI review)** — claim or restamp the lock to
   `ai-reviewer`; set the RD's frontmatter `state: ai_review` (bucketed `in_review`).
4. **Delegate — AI review (always runs first)** — dispatch `ai-reviewer` with the diff, DEVBOOK,
   and AC list. It checks AC coverage, RD-ID annotation, no scope creep, no `tests/**` edits.
   Verdict: pass/fail with findings. Record the wall-clock timestamp this dispatch returns as
   `ai_review.timestamp` — this is what makes the ordering invariant mechanically checkable
   rather than merely asserted.
5. **Claim + state transition (before security review, conditional)** — only if step 2 flagged
   hazard=high or leash=A+: restamp to `sec-reviewer`, set `state: sec_review`, dispatch it with
   the same diff. It checks for injection, secrets, auth bypass, unsafe external calls. If not
   triggered, record `security_review: "not_required"` with `timestamp: null` and skip the
   lock/state changes entirely — never fabricate a pass for a review that didn't run.
6. **Gate decision (always runs last)** — read `human_gates.gate` from `config/gates.yaml`
   (default `false`). If `true`: present AI (and security, if run) verdicts to the human for
   final approval/rejection — this cannot be skipped while the setting is `true`, even if both
   upstream checks passed. If `false`: this phase closes automatically once AI review (and
   security review, if triggered) both read `pass`/`not_required`. Any `fail` at the AI or
   security stage blocks approval regardless.
7. **Execute** — write `gate-records/<rd-id>-gate.json`:
   `{rd_id, ai_review:{verdict,findings,timestamp}, security_review:{verdict|"not_required",findings,timestamp|null}, gate_decision:{approver:"auto"|<human>,decision,timestamp}, order_enforced:true}`.
   The three timestamps must be chronologically non-decreasing — that's what `order_enforced:
   true` is actually claiming.
8. **Resolve state + lock (after decision)** — if `approved`: `state: accepted`, release the
   lock via `release-lock.sh` (durably records `rd_release` in telemetry). If `rejected`:
   emit `gate_rejected` before restamping (a plain restamp reads identically to a normal
   handoff, so rejection needs its own marker), set `state: red` (not `rejected` — that state
   is reserved for a terminal, non-retrying kill), restamp the lock back to `cz-build`. Clear
   stale heartbeat files for agents no longer actually working.
9. **Log** — append a Delivery Log entry to `deliverables/understanding-log/rd/$1.md`, and
   append an RD-specific Understanding Gate question (e.g. "Explain in plain terms what `$1`
   now lets a user do, and one way it could still fail."). Requires a human-authored answer
   before the RD is closed only when `human_gates.gate` is `true`; otherwise logged for
   visibility.
10. **Iterate** — any `fail` at any stage sends the RD back to `/cz:build $1` (re-enter the
    red-green loop, see the `sdd-loop` skill), not back to the gate directly.

Exit condition: `gate-records/<rd-id>-gate.json` has all applicable stages at
`pass`/`not_required`, `gate_decision` recorded, RD state reflects the outcome (`accepted` or
`red`, never left at `ai_review`/`sec_review`/`human_review`), and the claim lock is released or
handed back — AND, only when `human_gates.gate` is `true`, the RD-specific Understanding Gate
question is answered by a human.

## Light / Standard / Heavy comparison

| Gate element | **Light** | **Standard** | **Heavy (A+)** |
|---|---|---|---|
| Red proof before code | required for `layer: 0`; skippable for `layer: 1` with `red_skipped: true` recorded | every RD | every RD + AC-coverage threshold |
| AI review | 1 pass, short checklist | 1 pass, full checklist | 2 passes + adversarial + second model |
| Security review | skipped | on hazard-path touch | always |
| Human approval | 1 approval | approval + Understanding Gate | named reviewer + evidence link + hazard sign-off |
| Traceability | RTM optional; orphans warn | RTM required; orphans block the report | bidirectional + zero stale TCs |
| Delegation ceiling | L3, leash A | L3, leash A | L4, leash A+, per-action approval |
| Concurrency default | bounded 2 | bounded 3 | serial |
| Dev Book entry | per RD | per RD + ≥1 correction | per RD + correction + root cause |

**On the Light red-skip.** This is the one place a profile weakens a core guarantee, so it's
made expensive rather than quiet: applies only to surface (`layer: 1`) RDs, sets
`red_skipped: true` permanently on the record, emits a governance event, appears in the RTM,
and is counted on the board. `ai-reviewer` flags any `red_skipped` RD that should not have
qualified.

Note on the ceiling: Light gets a **lower** ceiling than Heavy, the opposite of intuition.
Anything that writes, changes systems, affects permissions, or touches sensitive data should
stop at L3 at most; hazard zones must move to controlled L4. L4 is not a reward for low-risk
work — it's a controlled mode that exists only in Heavy because Heavy is the only profile with
the gates that make it safe.

## `config/gates.yaml` shape

```yaml
profile: standard              # light | standard | heavy
delegation_ceiling: L3         # never above L4; L4 only under heavy
module_overrides:
  reconciliation: heavy         # hazard module, forced up
  notifications: light
concurrency:
  mode: bounded
  max_in_flight: 3
  wave_ceiling: 8
  hazard_mode: serial          # not overridable
  stall_threshold_s: 180
hazard_paths:                  # any diff touching these auto-escalates
  - "**/auth/**"
  - "**/permissions/**"
  - "**/migrations/**"
  - "**/*secret*"
  - "**/payment/**"
  - "**/pii/**"
  - ".github/workflows/**"
human_gates:                   # per-phase: does this phase's Gate step block on human sign-off?
  scope: true                  # only key defaulting true besides rd_commit
  rd_commit: true
  gate: false                  # default — see /cz:gate step 6
  # ...every other phase key defaults false
```

## Hazard escalation and the one-way ratchet

The hazard detector (`hooks/detect-hazard.sh`) inspects the **actual diff**, not the declared
module: a `light` module touching `**/auth/**` escalates to `heavy` for that change, and the
escalation is logged as a governance event. Invariants that cannot be overridden by any
profile:

- Hazard RDs always run serial, drained to zero in-flight before claim.
- `delegation_ceiling` never exceeds L4; L4 exists only under `profile: heavy`.
- `risk-gov` may *propose* a profile change; only a human commits it, and the commit is itself
  an audited governance event.
- A diff touching `hazard_paths` escalates to heavy for that change even if its module is
  light or standard.
- AI review (and security review, where triggered) always run, regardless of `human_gates`.
- `human_gates` is read fresh by each command at its own Gate step — a mid-project edit takes
  effect on the next phase run; it never retroactively reopens an already-passed
  `gate-records/*.json`.

## Hard-stop on contradiction

Per the Operating Model, *"AI stopped and asked" is a good signal, not a failure.* Any agent —
including the reviewers — detecting a contradictory or underspecified requirement opens
`HS-<proj>-<nnn>`, moves its RD to `blocked_hardstop`, and halts. The board surfaces it in the
header. A project with zero hard-stops across its full lifecycle is itself a mild warning sign.
