---
description: Render red/green test output and gate verdicts in plain language for non-coder PMs
argument-hint: [rd-id]
allowed-tools: Read, Write(deliverables/EXPLAIN*.md), Grep, Glob, Task
---

Translates the technical evidence for RD `$1` into plain language for a PM who does not read test logs or diffs.

1. **Context** — load `evidence/RD-$1/tests-red-vN.log`, the paired green log, `deliverables/DEVBOOK-$1.md`, and `gate-records/$1-gate.json`.
2. **Plan** — identify the three things a non-coder PM actually needs: (a) what behavior was being tested, in one sentence tied to the RD's AC; (b) what "red" meant here — specifically what failed and why that's expected/good at that stage, not a bug; (c) what "green" means now — that the same test, unchanged, passes.
3. **Delegate** — dispatch to a general-purpose agent (or reuse `ai-reviewer`'s context if already loaded from `/cz:gate`) via Task with the raw logs and DEVBOOK, instructing it to avoid jargon (no "assertion", "stack trace", "mock" without a plain-language gloss) and to explicitly state the byte-identical red/green test guarantee in human terms ("the same check was used before and after, so we know the fix — and only the fix — made it pass").
4. **Execute** — print (do not write a new artifact by default — this is a conversational explainer) a short walkthrough: AC in plain terms -> red result in plain terms -> green result in plain terms -> gate verdicts (AI/security/human) in plain terms -> what a PM should tell stakeholders.
5. **Gate** — none; this is an explanatory read of already-gated evidence, not a new gate.
6. **Log** — none by default; if the PM wants a durable copy, save it under `deliverables/EXPLAIN-$1.md` on request (prepend `kind: EXPLAIN`/`rd: $1`/`step: n/a` frontmatter per docs/DELIVERABLES.md so it auto-renders to HTML), but this is optional.
7. **Iterate** — if the PM asks a follow-up ("what does 'stale TC' mean for this RD?"), keep answering in the same plain-language register, tying every answer back to the specific evidence files for `$1`.

Exit condition: the PM can restate, in their own words, what was tested and why it's trustworthy — this command exists specifically to make that possible without reading code.
