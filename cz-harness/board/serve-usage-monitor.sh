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
rm -f "$MERGED_DIR"/*.jsonl "$MERGED_DIR"/*.subagents.json

# One merged file per project (top-level session logs), plus one
# <project>.subagents.json per project holding each session's subagent
# trajectories from the <sessionId>/subagents/ sidecar folders next to each
# top-level *.jsonl — every thinking/tool_use/tool_result/text step a
# Task/Agent-spawned subagent produced, keyed by sessionId then toolUseId
# (the toolUseId links back to the parent transcript's Task tool_use block).
python3 - "$PROJECTS_DIR" "$MERGED_DIR" <<'PYEOF'
import json, os, sys

projects_dir, merged_dir = sys.argv[1], sys.argv[2]
manifest = []

TEXT_CAP = 4000
INPUT_CAP = 2000

def cap(s, limit):
    if s is None:
        return ""
    if len(s) <= limit:
        return s
    return s[:limit] + "…[truncated, %d more chars]" % (len(s) - limit)

def summarize_content(content):
    """Turn a message.content value (str or list of blocks) into step dicts."""
    steps = []
    if isinstance(content, str):
        if content.strip():
            steps.append({"kind": "text", "text": cap(content.strip(), TEXT_CAP)})
        return steps
    if not isinstance(content, list):
        return steps
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get("type")
        if btype == "thinking":
            t = block.get("thinking") or ""
            if t.strip():
                steps.append({"kind": "thinking", "text": cap(t.strip(), TEXT_CAP)})
        elif btype == "text":
            t = block.get("text") or ""
            if t.strip():
                steps.append({"kind": "text", "text": cap(t.strip(), TEXT_CAP)})
        elif btype == "tool_use":
            try:
                input_str = json.dumps(block.get("input", {}), ensure_ascii=False)
            except Exception:
                input_str = str(block.get("input"))
            steps.append({
                "kind": "tool_use", "name": block.get("name", "?"),
                "input": cap(input_str, INPUT_CAP),
            })
        elif btype == "tool_result":
            rc = block.get("content")
            if isinstance(rc, list):
                rc = "\n".join(
                    (c.get("text") or "") for c in rc if isinstance(c, dict)
                )
            elif not isinstance(rc, str):
                rc = json.dumps(rc, ensure_ascii=False) if rc is not None else ""
            steps.append({
                "kind": "tool_result", "isError": bool(block.get("is_error")),
                "text": cap((rc or "").strip(), TEXT_CAP),
            })
    return steps

def parse_subagent_transcript(path):
    """One subagent's full trajectory: ordered list of {ts, kind, ...}."""
    steps = []
    try:
        with open(path, "r", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                ts = d.get("timestamp")
                msg = d.get("message") or {}
                for step in summarize_content(msg.get("content")):
                    step["ts"] = ts
                    step["role"] = msg.get("role")
                    steps.append(step)
    except Exception:
        pass
    return steps

def collect_subagents(session_dir):
    """sessionDir/subagents/agent-*.jsonl + matching .meta.json -> list of runs."""
    sub_dir = os.path.join(session_dir, "subagents")
    if not os.path.isdir(sub_dir):
        return []
    runs = []
    for fname in sorted(os.listdir(sub_dir)):
        if not fname.endswith(".jsonl"):
            continue
        agent_id = fname[:-len(".jsonl")]
        meta_path = os.path.join(sub_dir, agent_id + ".meta.json")
        meta = {}
        if os.path.isfile(meta_path):
            try:
                with open(meta_path, "r", errors="ignore") as mf:
                    meta = json.load(mf)
            except Exception:
                meta = {}
        steps = parse_subagent_transcript(os.path.join(sub_dir, fname))
        if not steps and not meta:
            continue
        runs.append({
            "agentId": agent_id,
            "toolUseId": meta.get("toolUseId"),
            "agentType": meta.get("agentType"),
            "description": meta.get("description"),
            "spawnDepth": meta.get("spawnDepth", 1),
            "steps": steps,
        })
    return runs

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

    subagents_by_session = {}
    for fname in jsonl_files:
        session_id = fname[:-len(".jsonl")]
        session_dir = os.path.join(proj_path, session_id)
        if os.path.isdir(session_dir):
            runs = collect_subagents(session_dir)
            if runs:
                subagents_by_session[session_id] = runs
    subagents_out_path = os.path.join(merged_dir, name + ".subagents.json")
    with open(subagents_out_path, "w") as sf:
        json.dump(subagents_by_session, sf)

    label = name[1:] if name.startswith("-") else name
    manifest.append({
        "name": label,
        "file": "merged/" + name + ".jsonl",
        "subagentsFile": "merged/" + name + ".subagents.json",
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
