---
description: Print a text projection of the live board, including agent stall detection
allowed-tools: Read, Bash, Grep, Glob
---

Prints a terminal-friendly projection of the same data `board/board.html` renders from `state/board.json` — for when a human wants the status without opening a browser.

1. **Context** — read `state/board.json` (current wave, gate profile, concurrency mode, per-RD status) and the tail of `telemetry/events.jsonl` for recent heartbeats.
2. **Plan** — group RDs by status: `not_started`, `claimed`, `red`, `green`, `refactor`, `gating`, `done`, `blocked`. For each RD currently `executing` (an agent actively working it), compute time since its last heartbeat event in `telemetry/events.jsonl`.
3. **Execute** — print a table: RD ID | module | status | agent | last heartbeat age | gate profile note. Flag any RD where an agent is "executing" but the last heartbeat is **older than 180 seconds** as `STALLED` — call this out prominently (e.g. a leading warning line: "N agents stalled").
4. **Execute (cont.)** — below the table, print a one-line wave summary (current wave number, near-term-wave RD count remaining, next-wave feature count) and the active gate profile + concurrency mode from `/cz:init`.
5. **Gate** — none; this is a read-only reporting command, no artifact is committed and no gate record is written.
6. **Log** — none; status checks are not logged to `deliverables/understanding-log/**` (they are not delivery events).
7. **Iterate** — n/a; re-run anytime for a fresh snapshot.

Exit condition: none — this command is idempotent and side-effect free. If it finds stalled agents, it should suggest `/cz:audit` (to check whether telemetry and board state have diverged) or manually re-claiming the RD.
