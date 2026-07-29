# Operator Guide — Day One for a Non-Coder PM

This guide assumes you can read, but not necessarily write, code. It walks through what
`/cz:init` sets up, the real phase pipeline, the real per-RD build-and-review loop, how to read
the live board, what a hard-stop is and what you do about it, and where to look when something
seems stuck. Every command name and state name below is taken directly from the plugin's actual
commands (`commands/*.md`) and its state-machine enforcement hook
(`hooks/guard-state-transition.sh`) — if a command or state isn't in this document, it doesn't
exist in the harness yet.

## 1. `/cz:init` — Scaffold the Project

`/cz:init <project-code>` (e.g. `/cz:init PB01`) is the very first thing you run, and it is not
one of the numbered pipeline phases below — it's the prerequisite that gives `/cz:scope`
somewhere to write. Run it once per project; it refuses to run again once `state/board.json`
already exists (that protects you from re-scaffolding over live state — use `/cz:status`
instead to check on an existing project).

It asks you to decide two project-wide settings up front, because they shape how every later
command behaves:

- **Gate profile** — `light`, `standard` (the default), or `heavy`. This controls how strict
  reviews are, whether red-proof (the failing-test-first step) can ever be skipped, and whether
  a missing link in the traceability chain blocks `/cz:report` or just warns. See
  `docs/LIGHTWEIGHT-MODE.md` for when Light is a legitimate choice versus a loophole.
- **Concurrency mode** — `serial` (one RD claimed at a time), `bounded` (up to N RDs in flight,
  you set N — the default), or `wave` (every current-wave RD may be claimed in parallel, still
  respecting module dependency order). If you're new to the harness, start conservative.

It also writes `config/gates.yaml`, which is where per-phase **human sign-off** lives —
separately from the profile choice. By default, every phase key in `human_gates` requires a
human sign-off (`true`); Phase 0 (`scope`) is the one key the harness always treats as `true`
even if the line is ever missing from the file, since that's the project's last unconditional
checkpoint. A PM can lower any other phase's `human_gates` key later by editing
`config/gates.yaml` directly — no gate is required for that edit, but it's worth doing
deliberately, not by accident.

`/cz:init` creates the runtime folders a project needs (`rd/`, `tests/`, `evidence/`,
`gate-records/`, `telemetry/`, `state/`, `deliverables/`, plus a few nested subfolders) and seeds
`state/board.json` — the file the live board and `/cz:status` both read from. Once this exists,
`/cz:scope <project-code>` may run.

## 2. The Pipeline — 11 Numbered Phases Plus RD Decomposition

CZ-Harness runs delivery as 11 numbered phase commands (0 through 10), each producing the
artifact the next phase needs, plus one non-numbered but essential step — `/cz:rd` — that turns
a wave of planning into actual claimable work. A later phase refuses to run if its required
input artifact and gate record don't exist yet, so you cannot accidentally skip ahead.

| # | Command | Produces | Notes |
|---|---|---|---|
| 0 | `/cz:scope <code>` | `deliverables/SCOPE-<code>.md` | Problem, goals, non-goals, stakeholders, constraints, open questions (`OQ-<code>-nnn`). Human sign-off is on by default and is the one phase that can't quietly be turned off later without you noticing (see above). |
| 1 | `/cz:spec <code>` | `deliverables/SPEC-<code>.md` | Turns Goals into numbered `REQ-<code>-nnn` requirements. |
| 2 | `/cz:modulemap <code>` | `deliverables/MODULEMAP-<code>.md` | Partitions every REQ into exactly one module, and marks each module `layer: 0` (foundation) or `layer: 1` (surface). |
| 3 | `/cz:arch <code>` | `deliverables/ARCH-<code>.md` | Per-module interfaces, data shapes, and design decisions, foundation modules designed before the surface modules that depend on them. |
| 4 | `/cz:wbs <code>` | `deliverables/WBS-<code>.md` | A rolling-wave work breakdown — the near-term wave decomposed to task level, later waves left coarse until their turn. |
| 5 | `/cz:estimate <code>` | `deliverables/EST-<code>.md` | Rolls up RD-level three-point estimates (PERT) per WBS branch into a project total. |
| 6 | `/cz:risk <code>` | `deliverables/RISK-<code>.md`, `deliverables/DELEGATION-MAP-<code>.md` | Assigns each module a hazard rating and a leash (autonomy) rating — this is what later decides whether a security review is mandatory for an RD. |
| — | `/cz:rd <wbs-leaf-id>` | new/updated files under `rd/` | Decomposes the **current wave only** into RDs, checking all six validity rules (see `docs/RD-GUIDE.md`). Committing every RD and every split is a human action by default — this is one of only two `human_gates` keys that default to `true`. |
| 7 | `/cz:dor <rd-id>` | `deliverables/DOR-<rd-id>.md` | Definition of Ready, evaluated **per RD**, not once per project. Passing this is what actually moves an RD's `state` from `draft`/`blocked_dep` to `ready` — nothing else does. |
| 8 | `/cz:build <rd-id>` | working code, `deliverables/DEVBOOK-<rd-id>.md` | The red-green-refactor loop — see §3. |
| 9 | `/cz:gate <rd-id>` | `gate-records/<rd-id>-gate.json` | The fixed-order review gate — see §3. |
| 10 | `/cz:report <code>` | `deliverables/RTM-<code>.md`, `deliverables/WEEKLY-<code>.md`, `deliverables/CASE-STUDY.md` | Traceability matrix, orphan scan, telemetry rollup, and the stakeholder-facing weekly narrative. |

Phases 7 through 9 run **per RD**, not once per project — a real project can have dozens of RDs
moving through `/cz:dor` → `/cz:build` → `/cz:gate` at once (under `bounded`/`wave`
concurrency), each tracked independently, while phases 0–6 and 10 run at the project or wave
level.

If you'd rather not drive each of these by hand, `/cz:run <code>` is the unattended
orchestrator: it repeatedly asks for the next eligible unit of work (a phase or an RD) and
drives it with the same commands you'd have typed yourself, but it **stops itself** the instant
a human sign-off is due, a hard-stop appears (§5), the per-wave budget cap is hit, or there's
nothing left to schedule. It writes no gate record and flips no `human_gates` value of its own —
when it stops, it names exactly which command or decision is waiting on you.

## 3. The RD Inner Loop — Claim, Red, Green, Review, Accepted

An RD (Requirement Detail) is the smallest unit of claimable, testable, gate-able work. Once
`/cz:dor` has passed for an RD, its `state` field (in `rd/<rd-id>.md`'s frontmatter) reads
`ready`, and it can be claimed. Every RD state transition is enforced by one hook —
`hooks/guard-state-transition.sh` — which rejects any transition not in its table. That table
*is* the real state machine; the state names below are exactly the ones it uses, nothing
invented for this guide:

```
ready --claim--> claimed --test-designer writes the red test--> red
                                                                  |
                                                        dev implements, tests pass
                                                                  v
                                                                green
                                                                  |
                                                         ai-reviewer attaches
                                                                  v
                                                              ai_review
                                                    (hazard / leash-A+ only --> sec_review)
                                                                  v
                                                            human_review
                                                             /          \
                                                       accepted        rejected
                                                                           |
                                                                          red   (back into the build loop)
```

In practice this is `/cz:build <rd-id>` followed by `/cz:gate <rd-id>`:

1. **Claim** (`ready → claimed`). An agent takes the lock on the RD. This is also the moment the
   live board starts showing a real agent name against that RD instead of `unknown`.
2. **Red** (`claimed → red`). The `test-designer` agent writes 1–3 test cases straight from the
   RD's acceptance criteria — the `dev` agent never sees them. The tests are run and **must
   fail**; that failing run is the "red proof," logged under `evidence/`.
3. **Green** (`red → green`). The `dev` agent implements the minimum code to pass, without ever
   seeing the test file contents. The same tests are re-run and must now pass, with the test
   file bytes **byte-identical** to the red run — if the test changed in between, the loop is
   invalid and restarts from Red. An optional refactor pass can happen here as long as tests
   stay green throughout.
4. **Review, in fixed order** (`green → ai_review`, then conditionally `→ sec_review`, then
   `→ human_review`). AI review always runs first and checks acceptance-criteria coverage,
   RD-ID annotation on the touched code, and that nothing beyond the RD's own statement got
   changed. A security review is inserted only if the RD's module carries a `high` hazard
   rating or an `A+` (tightened — hazard / heavy-profile) leash rating per `/cz:risk`'s output —
   otherwise it's skipped and recorded as `not_required`, never silently assumed to have passed. A human
   decision is always the last stage; whether it actually pauses for a person depends on
   `human_gates.gate` in `config/gates.yaml` (default `false`, meaning it auto-resolves once AI
   review — and security review, if triggered — both come back `pass`).
5. **Outcome**. Approval moves the RD to `accepted` and releases its claim lock — done. A
   rejection at any review stage moves the RD to `rejected` and then back to `red`, so it
   re-enters the build loop rather than needing a fresh claim from scratch.

One legitimate shortcut exists: under `light` profile, a `layer: 1` (surface) RD may skip
straight from `claimed` to `green` with no red proof at all — but only with `red_skipped: true`
permanently recorded on the RD, a governance event logged, and a visible flag on the board and
RTM. See `docs/LIGHTWEIGHT-MODE.md`. There is no other way to reach `green` without a red proof.

If a red/green result or a gate verdict is written in language you can't parse, run
`/cz:explain <rd-id>` — it translates the raw test logs and gate verdicts into a plain-language
walkthrough (what was tested, what "red" meant here, what "green" now proves) written for a PM
who isn't going to read the diff. It's read-only, so running it is always safe.

## 4. Reading the Board

`/cz:board` opens the live board (`board/board.html`) in your browser, served locally against
the current project's `state/board.json`. `/cz:status` prints the same information as text in
the terminal, if you'd rather not switch to a browser. Both are pure, read-only views of
`state/board.json` — neither one writes anything, and neither is the source of truth (that's
`telemetry/events.jsonl`, an append-only log — see §6 if the board and reality ever disagree).

The board groups every RD into a bucket, derived straight from its `state` field:

| Bucket | RD states inside it | Meaning |
|---|---|---|
| Ready | `ready` | Passed DoR, waiting to be claimed. |
| In flight | `claimed`, `red`, `green` | An agent is actively holding the lock and working it — this is what counts against your concurrency limit. |
| In review | `ai_review`, `sec_review`, `human_review` | Being reviewed. This does **not** count against your concurrency limit, so a slow review never blocks new work from starting. |
| Accepted | `accepted` | Done. |
| Blocked (dependency) | `blocked_dep` | Waiting on another RD to reach `accepted` first. |
| Hard-stop | `blocked_hardstop` | See §5. |
| Stale | `stale` | A normative field changed after tests were written (or even after acceptance) and the RD needs a fresh look before continuing. |
| Withdrawn | `withdrawn` | Deliberately descoped by a human; terminal — it cannot be reopened. |

For any RD an agent is actively working, the board also shows time since its last heartbeat. If
that's over 180 seconds, the RD is flagged **stalled** — this is computed on the spot from the
heartbeat timestamp, not something an agent reports about itself (a genuinely hung agent can't
tell you it's hung). A stalled RD is worth a look, not necessarily a panic — see §6.

## 5. Hard-Stops — What They Look Like and What You Do

A hard-stop means an agent — any of them, the rule applies uniformly — hit a genuine
contradiction or something underspecified that it is not allowed to resolve on its own. When
that happens, the affected RD's `state` moves to `blocked_hardstop`, and an `HS-<project>-<nnn>`
entry appears in `state/board.json`'s `hard_stops[]` list. You'll see it called out on the board
and in `/cz:status`'s output — this is one of the handful of things the board is specifically
designed to make impossible to miss.

What to do:

1. Read the hard-stop's description — it names the specific contradiction, not just "stuck."
2. Resolve it. This is a judgment call only a human makes; the harness does not let any agent
   close its own hard-stop.
3. Once resolved, the RD moves back either to the state it was in before the hard-stop was
   raised, or to `stale` if resolving it meant editing the RD itself — which then needs a fresh
   look before it can re-enter `red`.

Until you resolve it, `/cz:run` (the unattended driver) refuses to even start — checking for an
open hard-stop is the first thing it does, on every invocation. There is no path from
`blocked_hardstop` to `accepted` for an RD until a human has explicitly dealt with it.

## 6. Something Seems Stuck — Where to Look

- **`/cz:status` first.** It's the fastest read: every RD's current state, anything flagged
  stalled (executing with no heartbeat for 180+ seconds), and the current wave, gate profile,
  and concurrency mode in one line. If something looks stalled, this is usually where you
  notice it first.
- **`/cz:audit <project-code>`** if the board itself seems wrong — it disagrees with what you
  remember happening, or a count doesn't add up. This retroactively replays the immutable
  telemetry log and git history and diffs that fresh replay against the live board, calling out
  anything that looks like a real invariant was violated (not just a rendering lag). A genuine
  mismatch is treated as an incident to escalate to you, not something to silently patch over.
- **`/cz:rebuild-state <project-code>`** once you know the board is just stale or out of sync,
  not a governance incident — it regenerates `state/board.json` from scratch. This is the
  recovery path `/cz:board` and `/cz:audit` both point to when the live board and the underlying
  log disagree.
- **`/cz:viva <project-code>`** before a stakeholder review or audit conversation — it rehearses
  the kinds of questions a governance review will ask, grounded in the project's own artifacts,
  so you aren't improvising answers on the day.

If you take away one thing from this guide: the board and `/cz:status` are cheap and safe to
check anytime — check them first. `/cz:audit` and `/cz:rebuild-state` exist specifically for the
moment a quick look isn't enough.
