#!/bin/bash
# Merges every project's Claude Code session logs under ~/.claude/projects/*/
# into one manifest.json + one merged/<project>.jsonl per project, serves
# that alongside a copy of usage-monitor.html over a local HTTP server (the
# dashboard's optional auto-load block only activates over http(s), never
# file://), and opens it in the default browser.
#
# Safe no-op fallback: if anything here fails, the caller should fall back to
# opening board/usage-monitor.html directly as a file:// URL (sample data +
# manual "Load Claude log..." picker), which needs no server at all.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_HTML="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/board/usage-monitor.html"
[ -f "$BASE_HTML" ] || BASE_HTML="$SCRIPT_DIR/usage-monitor.html"

RUN_DIR="$HOME/.claude/usage-monitor-run"
PROJECTS_DIR="$HOME/.claude/projects"
MERGED_DIR="$RUN_DIR/merged"
PORT="${USAGE_MONITOR_PORT:-8791}"
PIDFILE="$RUN_DIR/server.pid"

if [ ! -f "$BASE_HTML" ]; then
  echo "Could not find usage-monitor.html (looked at $BASE_HTML)." >&2
  exit 1
fi
if [ ! -d "$PROJECTS_DIR" ]; then
  echo "No $PROJECTS_DIR found — nothing to merge." >&2
  exit 1
fi

mkdir -p "$MERGED_DIR"
rm -f "$MERGED_DIR"/*.jsonl

# One merged file per project (top-level session logs only; the per-session
# sidecar subfolders next to each *.jsonl are not additional log data).
python3 - "$PROJECTS_DIR" "$MERGED_DIR" <<'PYEOF'
import json, os, sys

projects_dir, merged_dir = sys.argv[1], sys.argv[2]
manifest = []

for name in sorted(os.listdir(projects_dir)):
    proj_path = os.path.join(projects_dir, name)
    if not os.path.isdir(proj_path):
        continue
    jsonl_files = sorted(
        f for f in os.listdir(proj_path)
        if f.endswith(".jsonl") and os.path.isfile(os.path.join(proj_path, f))
    )
    if not jsonl_files:
        continue
    out_path = os.path.join(merged_dir, name + ".jsonl")
    total_bytes = 0
    with open(out_path, "w") as out:
        for fname in jsonl_files:
            with open(os.path.join(proj_path, fname), "r", errors="ignore") as src:
                data = src.read()
                out.write(data)
                if data and not data.endswith("\n"):
                    out.write("\n")
                total_bytes += len(data)
    label = name[1:] if name.startswith("-") else name
    manifest.append({
        "name": label,
        "file": "merged/" + name + ".jsonl",
        "sessionFiles": len(jsonl_files),
        "bytes": total_bytes,
    })

with open(os.path.join(os.path.dirname(merged_dir), "manifest.json"), "w") as mf:
    json.dump({"projects": manifest}, mf, indent=2)

print(f"Merged {len(manifest)} project(s) into {merged_dir}")
PYEOF

cp "$BASE_HTML" "$RUN_DIR/index.html"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  sleep 0.3
fi
( cd "$RUN_DIR" && nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 & echo $! > "$PIDFILE" )
sleep 0.4

URL="http://127.0.0.1:$PORT/index.html"
case "$(uname -s)" in
  Darwin) open "$URL" ;;
  Linux) xdg-open "$URL" ;;
  MINGW*|MSYS*|CYGWIN*) start "$URL" ;;
  *) echo "Open $URL in your browser." ;;
esac
