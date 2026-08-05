---
description: Open the bundled Claude Usage Monitor dashboard in the default browser
allowed-tools: Bash
---

Opens the Claude Usage Monitor dashboard — a separate, standalone tool (token usage, model/agent/skill stats, prompt analytics, sessions). It is not part of the cz-harness board/state model; this command is a convenience launcher only.

1. **Context** — the dashboard ships as a static, self-contained file inside the plugin at `board/usage-monitor.html`: no server, no network calls, no dependency on this project's `state/board.json` or any cz-harness runtime state. It renders built-in sample data by default; its own "Load Claude log…" button reads a local `.jsonl`/`.log` file client-side via the browser's File API (nothing is uploaded). Because it never `fetch()`es anything, it's safe to open directly as a `file://` URL — unlike `board/board.html`, it does not need a local HTTP server.
2. **Plan** — determine the OS-appropriate way to open a local file in the default browser (`open` on macOS, `start` on Windows, `xdg-open` on Linux).
3. **Execute** — open `"${CLAUDE_PLUGIN_ROOT}/board/usage-monitor.html"` in the default browser via Bash.
4. **Gate** — none; read-only viewer, no artifact or gate record is produced.
5. **Log** — none; opening the dashboard is not a delivery event.
6. **Iterate** — re-running this command just re-opens the same file; loading a different log is done inside the page itself via "Load Claude log…".
7. **Note** — this file is a bundled copy of the "Claude Usage Monitor" artifact published at `https://claude.ai/code/artifact/cce47a78-3918-4dc6-bbbb-32688a994f2b`. The two are not kept in sync automatically: if that hosted artifact is edited and republished, re-copy its HTML into `board/usage-monitor.html` and bump the plugin version to pick up the change.

Exit condition: a browser tab open on `board/usage-monitor.html`, served as a local file.
