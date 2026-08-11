#!/usr/bin/env bash
# PostToolUse hook (matcher: Write|Edit) — fires after a rd/*.md write lands
# on disk, only acts when the RD's on-disk state is now withdrawn/superseded
# (i.e. this write just killed its lineage). Non-blocking advisory only (log
# + telemetry, never cz_deny) — mirrors detect-hazard.sh's pattern. Added per
# /cz:health-check's 2026-08-10 AIBOOTCAMP run, which found both of these by
# hand, after the fact, with no mechanical check catching either at the
# moment they happened:
#
#   Freshness: 9 files under src/**/tests/** still cited a withdrawn/
#   superseded RD id in a `// RD-<id> content_hash: ...` header or comment —
#   a dead end for anyone tracing test/source -> RD forward.
#
#   Coverage: 2 REQs had gone "lineage-exhausted" — every RD ever cut against
#   them was withdrawn/superseded with no live successor — invisible to a
#   pure graph check (an RD file still exists on disk, it's just not live).
#
# Both checks fire at exactly the moment a transition makes them true, which
# is strictly more useful than only catching them retroactively at the next
# /cz:health-check run — but they stay advisory (not a deny) because neither
# condition is necessarily wrong: a dangling citation may just need
# re-pointing on someone's next pass, and a lineage-exhausted REQ may be
# mid-descope on purpose. See docs/TRACEABILITY.md.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

[ -n "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in
  */rd/*.md) : ;;
  *) exit 0 ;;
esac
[ -f "$FILE_PATH" ] || exit 0

STATE="$(cz_rd_field "$FILE_PATH" state | tr -d '[:space:]')"
case "$STATE" in
  withdrawn|superseded) : ;;
  *) exit 0 ;;   # only a just-killed RD is in scope for either check below
esac

RD_ID="$(cz_rd_field "$FILE_PATH" id | tr -d '[:space:]"')"
[ -n "$RD_ID" ] || RD_ID="$(basename "$FILE_PATH" .md)"

# --- Freshness: src/**/tests/** citing this now-dead RD id -----------------
for scan_dir in "$CZ_ROOT/src" "$CZ_ROOT/tests"; do
  [ -d "$scan_dir" ] || continue
  while IFS= read -r citing_file; do
    [ -n "$citing_file" ] || continue
    rel="${citing_file#"$CZ_ROOT"/}"
    if [ -f "$TELEMETRY_FILE" ] && grep "\"event\":\"citation_stale\"" "$TELEMETRY_FILE" 2>/dev/null \
         | grep "\"rd\":\"$RD_ID\"" | grep -q "\"result\":\"$(cz_json_escape "$rel")\""; then
      continue   # already flagged for this exact (rd, file) pair
    fi
    cz_log "STALE CITATION: $rel cites $RD_ID, whose state is now $STATE. /cz:health-check flags this as a Freshness gap — re-point the citation to whatever live RD now owns the behavior, or resolve it via the lineage-exhausted re-cut if no successor exists. See docs/TRACEABILITY.md."
    cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"unknown\",\"event\":\"citation_stale\",\"result\":\"$(cz_json_escape "$rel")\",\"rd_state\":\"$STATE\",\"error_type\":null}"
  done < <(grep -rlF "$RD_ID" "$scan_dir" 2>/dev/null || true)
done

# --- Coverage: has this REQ's entire RD lineage just gone dead? ------------
PARENT_REQ="$(cz_rd_field "$FILE_PATH" parent_req | tr -d '[:space:]"')"
if [ -n "$PARENT_REQ" ] && [ -d "$RD_DIR" ]; then
  ANY_ALIVE=0
  for f in "$RD_DIR"/*.md; do
    [ -f "$f" ] || continue
    [ "$(cz_rd_field "$f" parent_req | tr -d '[:space:]"')" = "$PARENT_REQ" ] || continue
    s="$(cz_rd_field "$f" state | tr -d '[:space:]')"
    case "$s" in
      withdrawn|superseded) : ;;
      *) ANY_ALIVE=1 ;;
    esac
  done
  if [ "$ANY_ALIVE" -eq 0 ]; then
    if [ -f "$TELEMETRY_FILE" ] && grep "\"event\":\"lineage_exhausted\"" "$TELEMETRY_FILE" 2>/dev/null \
         | grep -q "\"result\":\"$(cz_json_escape "$PARENT_REQ")\""; then
      : # already flagged for this REQ
    else
      cz_log "LINEAGE EXHAUSTED: $PARENT_REQ now has zero live RDs ($RD_ID just went $STATE, and it was the last one). /cz:health-check flags this as a Coverage gap — decompose a fresh RD via /cz:rd against $PARENT_REQ if this REQ still needs to be delivered. See docs/TRACEABILITY.md."
      cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":null,\"agent\":\"unknown\",\"event\":\"lineage_exhausted\",\"result\":\"$(cz_json_escape "$PARENT_REQ")\",\"error_type\":null}"
    fi
  fi
fi

exit 0
