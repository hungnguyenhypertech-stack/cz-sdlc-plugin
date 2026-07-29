#!/usr/bin/env bash
# PreToolUse hook — inspects the ACTUAL diff (not the declared module) against
# config/hazard-paths.yaml. Any match escalates the touching RD's effective
# profile to heavy for that change, regardless of config (plan §8.4 one-way ratchet).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(echo "$HOOK_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"/\1/')"
# CZ_ACTIVE_RD is rarely actually set (see lib/common.sh's "Identity
# fallback") — try to pull the RD id out of the touched path itself (correct
# even with several RDs claimed at once), then fall back to the ambiguous
# sole-active-lock guess only if that fails.
RD_ID="${CZ_ACTIVE_RD:-}"
[ -n "$RD_ID" ] || RD_ID="$(cz_extract_rd_id "$FILE_PATH")"
AGENT="${CZ_ACTING_AGENT:-}"
if [ -n "$RD_ID" ]; then
  [ -n "$AGENT" ] || AGENT="$(cz_lock_agent_for_rd "$RD_ID")"
else
  [ -n "$AGENT" ] || AGENT="$(cz_sole_lock_agent)"
  RD_ID="$(cz_sole_lock_rd)"
fi
RD_ID="${RD_ID:-unknown}"
AGENT="${AGENT:-unknown}"

HAZARD_FILE="$CZ_ROOT/config/hazard-paths.yaml"
[ -f "$HAZARD_FILE" ] || exit 0

MATCHED=""
while IFS= read -r glob; do
  glob="$(echo "$glob" | sed -E 's/^[[:space:]]*-[[:space:]]*"?//; s/"?[[:space:]]*$//')"
  [ -z "$glob" ] && continue
  # Translate a small subset of glob (**, *) to a regex for matching FILE_PATH.
  regex="$(echo "$glob" | sed -E 's/\*\*/.*/g; s/(^|[^.])\*/\1[^\/]*/g')"
  if echo "$FILE_PATH" | grep -Eq "$regex"; then
    MATCHED="$glob"
    break
  fi
done < <(awk '/^hazard_paths:/{f=1;next} f && /^[a-z]/{exit} f{print}' "$HAZARD_FILE")

if [ -n "$MATCHED" ]; then
  cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":\"$RD_ID\",\"agent\":\"$AGENT\",\"event\":\"hazard_escalation\",\"result\":\"escalated_to_heavy\",\"error_type\":null}"
  cz_log "HAZARD PATH MATCH ($MATCHED) on $FILE_PATH — $RD_ID escalated to profile: heavy for this change. Security review and A+ leash now apply regardless of module_overrides."
  # Non-blocking: escalation, not denial. The gate engine (cz:gate) reads this
  # event and enforces the heavier gate sequence; this hook only records the fact.
fi

exit 0
