---
description: Retro-check every invariant from git history and telemetry, diff board.json against a fresh replay
argument-hint: [project-code]
allowed-tools: Read, Bash, Grep, Glob, Task
---

Retroactively audits project `$1` for drift between the live projection (`state/board.json`) and the ground truth (`telemetry/events.jsonl` plus git history) — the same trust-but-verify posture applied to this whole harness.

1. **Context** — load `telemetry/events.jsonl` in full, `state/board.json`, every `gate-records/*.json`, and `git log --all --stat` for the project's rd/ tests/ src/ folders.
2. **Plan** — enumerate the invariants to re-check: (a) every red log's `content_hash` matches the RD's current `content_hash` at the time it was logged; (b) every green run's test source is byte-identical to its paired red run; (c) `guard-red-before-green` was never bypassed (no `src/**` commit exists without a preceding valid red log in the same RD's evidence folder); (d) `guard-rd-freeze` was never bypassed (no TC edit committed while its RD was mid-loop without a corresponding re-red); (e) gate order was respected (AI review timestamp < security review timestamp (if run) < gate_decision timestamp) in every `gate-records/*.json`; (f) every gate record whose phase has `human_gates.<phase>: true` in `config/gates.yaml` (checked as of that record's timestamp — see the note in `config/gates.yaml` on human_gates not being retroactive) has a non-`"auto"` approver — an `"auto"` approver on a phase configured for human sign-off is itself a finding, not something to silently accept.
3. **Delegate** — dispatch a general-purpose or `agentops`-style check via Task (this is a mechanical replay, not a domain judgment call) to run a **fresh replay**: rebuild a board projection from `telemetry/events.jsonl` alone, from scratch, using the same projection logic `/cz:rebuild-state` uses.
4. **Execute** — diff the fresh replay against the live `state/board.json`. Any field mismatch (RD status, wave number, gate profile, per-RD claim owner) is a finding. Cross-reference each mismatch against invariants (a)-(e) to explain *why* it diverged, not just *that* it diverged.
5. **Gate** — this command does not gate a deliverable; it produces an audit finding set. If findings exist, treat them as blocking for any pending `/cz:gate` or `/cz:report` run until resolved.
6. **Log** — append an audit summary to `deliverables/understanding-log/audit.md` (Delivery Log entry, no Understanding Gate question required for a routine clean audit; do add one if findings were serious, e.g. "Explain how the guard bypass in RD-X happened and what prevents recurrence.").
7. **Iterate** — if the replay and live board disagree with no invariant violation found (e.g. just a rendering lag), run `/cz:rebuild-state` to resync. If an invariant violation is found, that is a governance incident — do not silently patch `state/board.json`; escalate to the human.

Exit condition: a clean audit report (no invariant violations, replay matches live state) or an explicit incident writeup handed to the human.
