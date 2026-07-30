#!/usr/bin/env bash
# Callable directly (like guard-claim-lock.sh / restamp-lock.sh — see their
# header comments; none of the three are wired into hooks.json as a
# PreToolUse matcher). Releases an RD's claim lock at the end of its
# lifecycle (gate approved -> nothing should keep holding it) and durably
# records that release before the lock file disappears.
#
# Without this, state/locks/<rd>.lock is removed by whatever step closes the
# RD (see commands/cz-gate.md step 8) with no telemetry trail at all — once
# the file is gone, there is no way to later reconstruct that the RD was
# ever held, by whom, or when it let go. rd_claim (guard-claim-lock.sh) and
# lock_restamped (restamp-lock.sh) already cover claim and hand-off; this is
# the missing release-side event, named "rd_release" to pair with the
# schema's existing "rd_claim" (audit finding C7 found this hook previously
# emitted the unlisted name "lock_released" instead).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

RD_ID="${1:-}"
REASON="${2:-released}"
[ -n "$RD_ID" ] || cz_deny "release-lock requires an RD id"

LOCK_FILE="$LOCK_DIR/$RD_ID.lock"
if [ ! -f "$LOCK_FILE" ]; then
  cz_log "release-lock: $RD_ID has no active lock — nothing to release (no-op)"
  exit 0
fi

HELD_BY="$(awk -F= '/^agent=/{print $2}' "$LOCK_FILE")"
rm -f "$LOCK_FILE"

cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"$HELD_BY\",\"event\":\"rd_release\",\"result\":\"$REASON\"}"

# Best-effort cleanup: every agent that touched this RD (dev, test-designer,
# ai-reviewer, cz-build, ...) may still have a state/heartbeats/<agent>.hb
# file pinned to it with agent_state "executing" from its last dispatch. Once
# the RD's lock is released nothing will ever update those files again, so
# without this they sit frozen and read as a permanent false stall (board.html
# /cz:status derive "stalled" purely from agent_state=="executing" + heartbeat
# age). Delete rather than idle-in-place — a stale rd/timestamp pair from a
# finished RD carries no useful information, and project-state.sh's own
# state-crosscheck (see its heartbeat loop) covers any file this step misses.
if [ -d "$STATE_DIR/heartbeats" ]; then
  for hb in "$STATE_DIR/heartbeats"/*.hb; do
    [ -f "$hb" ] || continue
    hb_rd="$(cz_json_field "$hb" rd 2>/dev/null || true)"
    [ "$hb_rd" = "$RD_ID" ] && rm -f "$hb"
  done
fi

exit 0
