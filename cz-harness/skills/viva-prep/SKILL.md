---
name: viva-prep
description: Rehearse a human for a cz-harness governance review, stakeholder review, or audit conversation, grounded in the project's own artifacts. Invoke before a real /cz:viva session, before a stakeholder review, or whenever someone wants to practice defending an RD/gate/risk decision with concrete evidence rather than an improvised answer.
---

# Viva Prep

Governance reviews and audits ask questions a PM should be able to answer from the project's
own artifacts, not from memory or improvisation. This skill packages `commands/cz-viva.md`'s
mechanics so a rehearsal can be run (or a question set drafted) directly, grounded in what the
project actually produced.

## When to use this skill

- Preparing for a real governance review, stakeholder review, or audit of a cz-harness project.
- Running `/cz:viva <project-code>` (this skill IS that command's mechanics).
- Practicing how to defend a specific RD, gate decision, or risk rating with the evidence trail
  behind it, rather than a paraphrase of what the artifact says.

## What to load first (grounding, not guessing)

- `deliverables/SCOPE-$1.md`, `deliverables/SPEC-$1.md`, `deliverables/RISK-$1.md`
- `deliverables/RTM-$1.md` (if it exists)
- Every fragment under `deliverables/understanding-log/**` — phase-level files *and*
  `rd/*.md` fragments; read the whole tree, since Understanding Gate entries are split per
  phase/RD, not kept in one file.
- A sample of `gate-records/*.json`

Answers checked against these artifacts, not against what the human remembers thinking at the
time — the point of rehearsal is to catch a stale mental model before the real review does.

## The floor question set (extend, don't replace)

Treat these ~5 as the floor, not the ceiling — always add project-specific questions from the
loaded artifacts:

1. "Walk me through one RD end-to-end, from REQ to gated code — what proves it actually works?"
   (Answer should trace: REQ → RD → AC → TC → red log → green log → gate record → telemetry —
   see the `traceability` and `sdd-loop` skills for the actual chain.)
2. "Where in this project did a human override or reject an AI/agent proposal, and why?"
   (Pull from Dev Book corrections and gate `rejected` decisions — see the `devbook` skill.)
3. "Show me an orphan `/cz:report` caught (or would have caught) — what did fixing it involve?"
   (One of the seven RTM orphan classes — see the `traceability` skill.)
4. "Which module has the highest hazard/leash rating, and what compensating control exists?"
   (Cross-reference `RISK-$1.md`/`DELEGATION-MAP-$1.md` and the gate engine's hazard escalation
   — see the `gate-engine` skill.)
5. "If I picked a random Understanding Gate answer from `deliverables/understanding-log/**`,
   would it hold up as genuinely your own understanding, not a paraphrase of the artifact?"

## Drafting project-specific questions

Scan the loaded artifacts for the weakest-looking spots and turn each into a targeted question:

- A module with thin risk justification in `RISK-$1.md`.
- A `WEEKLY-$1.md` report with unresolved orphans.
- A gate record with unusually fast human-approval timestamps — a candidate rubber-stamp
  signal (see the `devbook` skill's rubber-stamp risk score).
- Any `red_skipped: true` RD — does the justification actually hold up, or was it a
  convenience skip on something that should have qualified for full red proof?

Aim for 3–5 additional questions beyond the floor set, each answerable only by someone who
actually understands the artifact, not someone who can recite its headline.

## Running the rehearsal

1. Present the combined question list one at a time, conversationally — not as a written quiz.
2. Let the human answer first, unprompted.
3. Check their answer against the underlying artifact and flag any factual mismatch — the goal
   is to catch a stale mental model, not to score or embarrass.
4. No gate is produced by this exercise — it is rehearsal, not an official gate. No
   `gate-records/*.json` entry results from a viva-prep session.
5. Optionally append a note to `deliverables/understanding-log/viva.md` if the rehearsal
   surfaced a genuine misunderstanding worth recording (e.g. "rehearsal revealed I couldn't
   explain why module X is leash A+ — revisit `deliverables/RISK-$1.md`").
6. Re-run before the actual review, or whenever the project has advanced enough waves that new
   artifacts (new RTM entries, new risk items) warrant fresh questions.

Exit condition: the human has rehearsed at least the floor set plus the project-specific
questions, with any surfaced gaps either resolved on the spot or explicitly noted for
follow-up before the real review.
