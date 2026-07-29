# Lightweight Mode (Light Profile)

Light is a legitimate, first-class profile for small projects — not a "training wheels off"
mode and not a way to route around governance you don't feel like doing. This document
describes exactly what Light changes, what it deliberately does not change, and how to tell
whether you're using it appropriately or using it as a loophole.

## Agent Collapse: 5 Agents Instead of 10

Under Light profile, the 10-role agent roster collapses to 5:

| Light-profile role | Absorbs |
|---|---|
| sub-pm | (unchanged) |
| ba+sa (merged) | business analyst + solution architect responsibilities |
| test-designer | (unchanged, never merged — see below) |
| dev | (unchanged) |
| ai-reviewer | absorbs security-reviewer's non-hazard-path checks; risk-gov and telemetry-analyst duties fold into sub-pm's reporting pass |

**The one collapse that never happens, under any profile: test-designer and dev stay
separate.** Merging test-designer into dev would let the same actor write both the failing
test and the code that makes it pass, which quietly defeats the point of SDD (spec-driven
development) — the whole reason the red-then-green loop is trustworthy is that the test was
authored independently of the implementation. Light saves overhead everywhere else, but not
here, because this is the one seam that actually makes the "red proof" meaningful in the first
place.

## The One Place Light Weakens a Core Guarantee

Everywhere else, Light is a reduction in *overhead*, not a reduction in *guarantee* — fewer
roles doing the same checks, not fewer checks. There is exactly one exception, and it is
handled deliberately rather than quietly:

**Red proof is skippable, but only for `layer:1` (surface) RDs.** A surface-layer RD — thin,
low-risk, typically cosmetic or configuration-only changes — may proceed directly to
implementation without a preceding failing test, if the assigned agent judges the behavior too
trivial to meaningfully test-first.

This skip is never silent:

- `red_skipped: true` is written to the RD record **permanently** — it is not cleared later
  even if tests are added retroactively. The record of the skip is part of the RD's history
  forever.
- A governance event is emitted to telemetry at the moment of the skip.
- The skip is counted and visible in two places: the RTM (as a distinct column/flag, not
  folded into "tested") and on the live board (a visible badge on the RD).
- **ai-reviewer actively flags any `red_skipped` RD that shouldn't have qualified** — i.e., if
  ai-reviewer's own assessment is that the RD wasn't actually surface-layer, it raises this as
  a review finding rather than deferring to the original judgment call. This is the harness's
  check against the skip being used opportunistically.

## Other Light-Profile Relaxations

- **Concurrency default: `bounded:2`.** Same default as Standard, not loosened further — Light
  reduces process overhead, it doesn't imply you should run more RDs in parallel with less
  oversight per RD.
- **Security review: skipped.** Folded into ai-reviewer's pass for non-hazard paths. Hazard
  paths (see `SECURITY-NOTES.md`) still auto-escalate regardless of profile — Light does not
  override the hazard-path list.
- **RTM: optional.** Orphans warn rather than block report generation (see `TRACEABILITY.md`
  severity table). You can still run `/cz:report` and get a useful matrix; it just won't refuse
  to generate over an orphan the way Standard/Heavy would.

## When Light Is Appropriate

- A small internal script or utility with a narrow, well-understood scope.
- A single function or narrowly-scoped fix where the blast radius of a mistake is small and
  easily reversible.
- A short-lived or exploratory project where the cost of full Standard-profile ceremony would
  exceed the value of the project itself.

## When Light Is a Loophole

Light stops being "appropriately lightweight" and starts being a loophole the moment it's used
to:

- Skip red proof on RDs that aren't actually surface-layer, just because it's faster — this is
  exactly what ai-reviewer's flag on `red_skipped` exists to catch, but the flag is a
  backstop, not a substitute for using the skip honestly in the first place.
- Avoid security review on a project that does, in fact, touch hazard paths — this doesn't
  actually work, since hazard-path escalation isn't profile-gated, but attempting to route
  around it by mis-declaring modules is a misuse pattern worth watching for.
- Run a project at meaningful scale or risk under Light purely to avoid RTM enforcement, rather
  than because the project is genuinely small.

If you find yourself choosing Light because Standard "feels like too much friction" for a
project that is not actually small, that is the signal to re-evaluate the profile choice, not
to relax around it.
