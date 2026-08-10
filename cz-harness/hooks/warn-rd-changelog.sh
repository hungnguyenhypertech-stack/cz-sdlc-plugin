#!/usr/bin/env bash
# PostToolUse hook (matcher: Write|Edit) — fires after a rd/*.md write lands
# on disk. Non-blocking advisory only (log + telemetry, never cz_deny) —
# mirrors detect-hazard.sh's pattern, not guard-rd-freeze.sh's. Added per
# /cz:health-check's 2026-08-10 AIBOOTCAMP run: 11 RDs at version >= 2, and
# 8 of them had no notes: change-log documenting what changed or why —
# invisible to the pipeline until a manual audit walked every RD by hand.
#
# Deliberately PostToolUse, not a PreToolUse hard block: a block would need
# to know whether the RESULTING file (after this write) has a non-empty
# notes: field, but an Edit tool call only carries old_string/new_string, not
# the whole file — reconstructing the merged result to check that reliably
# is exactly the kind of best-effort regex-over-a-fragment problem
# guard-state-transition.sh already documents the fragility of for its own
# NEW_STATE extraction. Reading the actual file after the write lands
# sidesteps that reconstruction problem entirely, at the cost of being
# advisory rather than a gate.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(echo "$HOOK_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"/\1/')"

[ -n "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in
  */rd/*.md) : ;;
  *) exit 0 ;;
esac
[ -f "$FILE_PATH" ] || exit 0

VERSION="$(cz_rd_field "$FILE_PATH" version | tr -d '[:space:]')"
[ -n "$VERSION" ] || exit 0
case "$VERSION" in ''|*[!0-9]*) exit 0 ;; esac   # not a bare integer — malformed/unreadable, skip rather than guess
[ "$VERSION" -ge 2 ] || exit 0                    # version 1 has nothing to change-log yet

RD_ID="$(cz_rd_field "$FILE_PATH" id | tr -d '[:space:]"')"
[ -n "$RD_ID" ] || RD_ID="$(basename "$FILE_PATH" .md)"

# cz_rd_field is a single-line scalar reader (hooks/lib/common.sh) — a
# multi-line YAML block scalar (notes: > or notes: |) reads as empty here,
# same as every other field this codebase parses this way. Every real notes:
# field in this project is already a single-line double-quoted string (see
# templates/rd-template.yaml), so this is consistent with actual usage, not
# a new limitation.
NOTES="$(cz_rd_field "$FILE_PATH" notes)"
[ -n "${NOTES// }" ] && exit 0   # documented — nothing to warn about

# Dedup: only warn once per (rd, version) — an agent touching an already-
# flagged RD again for an unrelated field must not re-flood telemetry with
# the same advisory on every subsequent write.
if [ -f "$TELEMETRY_FILE" ] && grep "\"event\":\"changelog_gap\"" "$TELEMETRY_FILE" 2>/dev/null \
     | grep "\"rd\":\"$RD_ID\"" | grep -q "\"rd_version\":$VERSION"; then
  exit 0
fi

cz_log "CHANGELOG GAP: $RD_ID is at version $VERSION with no notes: field documenting the change. /cz:health-check flags this as a Change-coupling gap (undocumented version bump). Add a single-line notes: field (see templates/rd-template.yaml) before this RD's next touch. See docs/TRACEABILITY.md."
cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"unknown\",\"event\":\"changelog_gap\",\"result\":\"no_notes_field\",\"rd_version\":$VERSION,\"error_type\":null}"

exit 0
