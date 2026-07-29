#!/usr/bin/env bash
# PreToolUse hook — fires on RD claim attempts. Enforces "one RD, one lock"
# and lazily reclaims TTL-expired locks (plan §6.3 invariants 2-3). No
# background daemon required.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

RD_ID="${1:-${CZ_ACTIVE_RD:-}}"
AGENT_ID="${CZ_ACTING_AGENT:-}"
[ -n "$RD_ID" ] && [ -n "$AGENT_ID" ] || cz_deny "guard-claim-lock requires an RD id and acting agent"

mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/$RD_ID.lock"
LOCK_TTL_S=1800
FRESH_CLAIM=1
if [ -f "$LOCK_FILE" ]; then FRESH_CLAIM=0; fi

if [ -f "$LOCK_FILE" ]; then
  LOCK_AGENT="$(awk -F= '/^agent=/{print $2}' "$LOCK_FILE")"
  LOCK_TS="$(awk -F= '/^ts=/{print $2}' "$LOCK_FILE")"
  # Was: `date -u -d "$LOCK_TS" +%s` — GNU-only syntax. BSD date (macOS) has no
  # -d flag, so that call always failed silently and fell back to `echo 0`,
  # making every lock's computed AGE ~current-epoch-seconds — always past
  # LOCK_TTL_S, so every claim (same agent OR a different, competing one)
  # silently took the "TTL expired, reclaim" branch below instead of ever
  # hitting the re-entrant-ok or deny paths. cz_iso_to_epoch (lib/common.sh)
  # already handles both GNU and BSD date correctly — use it instead of
  # reimplementing (broken) parsing here. Found by /cz:audit, 2026-07-29.
  LOCK_EPOCH="$(cz_iso_to_epoch "$LOCK_TS")"
  LOCK_EPOCH="${LOCK_EPOCH:-0}"
  NOW_EPOCH="$(date -u +%s)"
  AGE=$(( NOW_EPOCH - LOCK_EPOCH ))

  if [ "$AGE" -lt "$LOCK_TTL_S" ]; then
    if [ "$LOCK_AGENT" = "$AGENT_ID" ]; then
      exit 0   # re-entrant claim by the same agent, fine
    fi
    cz_deny "$RD_ID is locked by $LOCK_AGENT (age ${AGE}s < TTL ${LOCK_TTL_S}s) — one RD, one lock"
  fi

  # TTL expired: reclaim lazily, log it, fall through to re-lock below.
  cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"$AGENT_ID\",\"event\":\"lock_reclaimed\",\"result\":\"reclaimed_from_$LOCK_AGENT\"}"
fi

# Hazard invariant: before a hazard RD is claimed, in-flight work must be drained
# to zero (plan §6.3 invariant 1). This hook only checks; sub-pm's scheduler is
# responsible for not attempting the claim until drained — this is the backstop.
if cz_is_hazard "$RD_ID"; then
  IN_FLIGHT_COUNT="$(find "$LOCK_DIR" -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$IN_FLIGHT_COUNT" -gt 0 ]; then
    cz_deny "$RD_ID is hazard: true — cannot claim while $IN_FLIGHT_COUNT other RD(s) hold locks; hazard work runs alone"
  fi
fi

cat > "$LOCK_FILE" <<EOF
agent=$AGENT_ID
ts=$(cz_now)
EOF

# Only a genuinely new lock is "rd_claim" — an expired lock that was just
# reclaimed above already emitted "lock_reclaimed" (line ~30); emitting both
# for the same physical claim would double-count one lifecycle transition
# as two events for any consumer folding this stream (e.g. /cz:rebuild-state).
# Event name is "rd_claim" (schema's existing enum value, paired with
# "rd_release" in release-lock.sh) — audit finding C7 found this hook
# previously emitted the unlisted name "rd_claimed" instead.
if [ "$FRESH_CLAIM" -eq 1 ]; then
  cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"$AGENT_ID\",\"event\":\"rd_claim\",\"result\":\"ok\"}"
fi

exit 0
