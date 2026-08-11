#!/usr/bin/env bash
# PostToolUse hook (matcher: Write) — fires after every Write. If the write
# landed under deliverables/**/*.md, renders a sibling .html next to it using
# the shared template/stylesheet and rebuilds deliverables/index.html.
#
# Non-blocking by design: this hook only makes agent output easier for a
# human to review (plan: "every agent output is a deliverable, HTML for
# human-friendly review"). It must never deny a write or fail the tool call —
# see docs/DELIVERABLES.md.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(echo "$HOOK_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"/\1/')"

[ -n "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  */deliverables/*.md) ;;
  *) exit 0 ;;
esac

# _assets/ itself is never a rendered deliverable.
case "$FILE_PATH" in */deliverables/_assets/*) exit 0 ;; esac

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$DIR/..}"
TEMPLATE="$PLUGIN_ROOT/templates/deliverables/page.html.tmpl"
CSS_SRC="$PLUGIN_ROOT/templates/deliverables/style.css"

mkdir -p "$DELIVERABLES_DIR/_assets"
cp -f "$CSS_SRC" "$DELIVERABLES_DIR/_assets/style.css" 2>/dev/null || true

# cz_python probes by EXECUTING a candidate — `command -v python3` alone passed
# on Windows against an App Execution Alias stub that always fails, so this hook
# reported "render failed" on every single deliverable write and nothing (not
# even deliverables/index.json) was ever produced. See cz_python in lib/common.sh.
PYTHON_BIN="$(cz_python)"
if [ -z "$PYTHON_BIN" ]; then
  cz_log "render-deliverable: no working python3/python interpreter found, skipping HTML render for $FILE_PATH (non-blocking). Set CZ_PYTHON_BIN to point at one."
  exit 0
fi

"$PYTHON_BIN" "$DIR/lib/render_deliverable.py" render "$FILE_PATH" "$DELIVERABLES_DIR" "$TEMPLATE" \
  && cz_log "rendered $(basename "${FILE_PATH%.md}").html" \
  || cz_log "render-deliverable: render failed for $FILE_PATH (non-blocking)"

"$PYTHON_BIN" "$DIR/lib/render_deliverable.py" index "$DELIVERABLES_DIR" "$TEMPLATE" \
  || cz_log "render-deliverable: index rebuild failed (non-blocking)"

exit 0
