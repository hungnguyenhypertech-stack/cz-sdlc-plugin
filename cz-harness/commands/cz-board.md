---
description: Open the live board (board/board.html) against the current project's state/board.json
allowed-tools: Read, Bash, Grep, Glob
---

Opens the visual live board for humans who prefer a browser view over `/cz:status`'s text projection.

1. **Context** — verify `board/board.html` exists in the plugin's shared assets and `state/board.json` exists for the current project. `board.html` is a static file that reads `state/board.json` client-side via `fetch()` — it does not embed project data itself. Opening it directly via `file://` makes that `fetch()` fail with a CORS error ("Failed to fetch"), so the board must always be served over local HTTP, never opened as a bare file.
2. **Plan** — pick a free local port and confirm the server will be rooted at the project directory (the parent of both `board/` and `state/`), so `board/board.html`'s relative fetch of `../state/board.json` resolves to the correct project's file, not a stale copy from another project.
3. **Execute**:
   - Check whether a local server is already serving this project's board (e.g. an existing `python3 -m http.server` bound to a known port for this path); reuse it if so.
   - Otherwise start one rooted at the project directory, backgrounded and bound to localhost only, e.g.: `cd "<project-dir>" && nohup python3 -m http.server <port> --bind 127.0.0.1 > /tmp/cz-board-server.log 2>&1 &`
   - Verify both `http://127.0.0.1:<port>/board/board.html` and `http://127.0.0.1:<port>/state/board.json` return 200 before opening anything.
   - Open `http://127.0.0.1:<port>/board/board.html` in the default browser (`open` on macOS, `start` on Windows, `xdg-open` on Linux).
4. **Gate** — none; this is a read-only viewer, no artifact or gate record is produced.
5. **Log** — none; opening the board is not a delivery event.
6. **Iterate** — the board auto-refreshes from `state/board.json` as the file changes (or the human refreshes manually) — no need to re-run this command unless the browser tab was closed or the local server was stopped.
7. **Note** — `board/board.html`'s rendering is a pure projection of `state/board.json`, the same invariant `/cz:rebuild-state` and `/cz:audit` rely on; if the board ever looks wrong, the fix is `/cz:rebuild-state`, not editing `board.html`. If the local server needs to be stopped later, kill the background process — do not leave the user guessing that a stray server is still bound.

Exit condition: a browser tab open on `http://127.0.0.1:<port>/board/board.html`, served by a local HTTP server rooted at the project directory, reflecting the current project's live state.
