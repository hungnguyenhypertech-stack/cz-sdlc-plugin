---
description: Rehearse expected governance-review questions about the project before a stakeholder review or audit
argument-hint: [project-code]
allowed-tools: Read, Grep, Glob, Task
---

Rehearses the human for a governance review or audit conversation on project `$1`, drawing on the harness's own artifacts so answers are grounded, not improvised.

1. **Context** — load `deliverables/SCOPE-$1.md`, `deliverables/SPEC-$1.md`, `deliverables/RISK-$1.md`, `deliverables/RTM-$1.md` (if it exists), every fragment under `deliverables/understanding-log/**` (phase-level files plus `rd/*.md` — read the whole tree, not one file, since Understanding Gate entries are now split per phase/RD), and a sample of `gate-records/*.json`.
2. **Plan** — the expected-question list is explicitly extensible; treat the following ~5 as the floor, not the ceiling, and add project-specific ones from step 1's artifacts:
   - "Walk me through one RD end-to-end, from REQ to gated code — what proves it actually works?"
   - "Where in this project did a human override or reject an AI/agent proposal, and why?"
   - "Show me an orphan `/cz:report` caught (or would have caught) — what did fixing it involve?"
   - "Which module has the highest hazard/leash rating, and what compensating control exists?"
   - "If I picked a random Understanding Gate answer from `deliverables/understanding-log/**`, would it hold up as genuinely your own understanding, not a paraphrase of the artifact?"
3. **Delegate** — dispatch a general-purpose agent via Task to scan the loaded artifacts and draft 3-5 additional project-specific questions targeting the weakest-looking spots (e.g. a module with thin risk justification, a WEEKLY report with unresolved orphans, a gate record with unusually fast human-approval timestamps suggesting rubber-stamping).
4. **Execute** — present the combined question list to the human one at a time, conversationally. For each, let the human answer first, then check their answer against the underlying artifact and flag any factual mismatch (not to judge them, but to catch a stale mental model before the real review).
5. **Gate** — none; this is rehearsal, not an official gate. No `gate-records/*.json` entry is produced.
6. **Log** — optionally append a note to `deliverables/understanding-log/viva.md` if the rehearsal surfaced a genuine misunderstanding worth recording (e.g. "rehearsal revealed I couldn't explain why module X is leash A+ — revisit deliverables/RISK-$1.md").
7. **Iterate** — re-run before the actual review, or whenever the project has advanced enough waves that new artifacts (new RTM entries, new risk items) warrant fresh questions.

Exit condition: the human has rehearsed at least the floor set of questions plus the project-specific ones, with any surfaced gaps either resolved or explicitly noted for follow-up.
