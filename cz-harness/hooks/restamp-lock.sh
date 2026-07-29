#!/usr/bin/env bash
# Callable directly (like guard-claim-lock.sh — see its header comment and
# hooks.json's notes; neither is wired into hooks.json as a PreToolUse
# matcher). Re-labels an already-held RD lock's `agent=` field when
# /cz:build's inner loop hands work off between roles (test-designer -> dev
# -> back to the outer cz-build loop). This is a relabel WITHIN the same
# claim, not a competing claim attempt, so it deliberately skips
# guard-claim-lock.sh's contention/TTL logic — that logic exists to arbitrate
# between agents fighting over a claim, not to let the one flow that already
# holds an RD say "the part of me acting right now is called X".
#
# Every downstream hook that resolves "who is acting" by reading
# state/locks/<rd>.lock (see lib/common.sh's cz_lock_agent_for_rd /
# cz_sole_lock_agent) picks up the new name immediately on its next fire —
# no restart needed.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

RD_ID="${1:-}"
NEW_AGENT="${2:-}"
[ -n "$RD_ID" ] && [ -n "$NEW_AGENT" ] || cz_deny "restamp-lock requires an RD id and a new agent name"

LOCK_FILE="$LOCK_DIR/$RD_ID.lock"
[ -f "$LOCK_FILE" ] || cz_deny "$RD_ID has no active lock to restamp — claim it via guard-claim-lock.sh first"

OLD_AGENT="$(awk -F= '/^agent=/{print $2}' "$LOCK_FILE")"

cat > "$LOCK_FILE" <<EOF
agent=$NEW_AGENT
ts=$(cz_now)
EOF

cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"$NEW_AGENT\",\"event\":\"lock_restamped\",\"result\":\"restamped_from_$OLD_AGENT\"}"

exit 0
