---
description: Open the published Claude Usage Monitor artifact in the default browser
allowed-tools: Bash
---

Opens the Claude Usage Monitor dashboard — a separate, standalone artifact (token usage, model/agent/skill stats, prompt analytics, sessions). It is not part of the cz-harness board/state model; this command is a convenience launcher only.

1. **Context** — the artifact is hosted at a fixed claude.ai URL, not a local file. It has no dependency on this project's `state/board.json` or any cz-harness runtime state.
2. **Plan** — determine the OS-appropriate way to open a URL in the default browser (`open` on macOS, `start` on Windows, `xdg-open` on Linux).
3. **Execute** — open `https://claude.ai/code/artifact/cce47a78-3918-4dc6-bbbb-32688a994f2b` in the default browser via Bash.
4. **Gate** — none; read-only viewer, no artifact or gate record is produced.
5. **Log** — none; opening the dashboard is not a delivery event.
6. **Iterate** — the artifact only updates when you re-publish it (via the Artifact tool) or manually reload a log inside it; re-running this command just re-opens the same tab.
7. **Note** — if the artifact URL changes (e.g. it gets republished under a new link), update the URL in this file to match.

Exit condition: a browser tab open on the Claude Usage Monitor artifact.
