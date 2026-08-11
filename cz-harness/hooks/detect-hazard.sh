#!/usr/bin/env bash
# PreToolUse hook — inspects the ACTUAL diff (not the declared module) against
# config/hazard-paths.yaml. Any match escalates the touching RD's effective
# profile to heavy for that change, regardless of config (plan §8.4 one-way ratchet).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"
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
# RD_ID stays EMPTY when identity can't be resolved — it is serialized as a
# bare JSON null below, never the string "unknown". telemetry-event.schema.json
# types rd as ["string","null"] with a strict pattern and says outright that
# emitters "must never coerce this into a fake pattern-matching placeholder
# just to satisfy this field": `"rd":"unknown"` matched neither branch, so this
# hook was emitting schema-invalid lines on the single highest-severity event
# type in the system. "unknown" remains correct for AGENT — it is an explicit,
# documented member of that field's enum.
AGENT="${AGENT:-unknown}"

RD_JSON="null"
[ -n "$RD_ID" ] && RD_JSON="\"$RD_ID\""
RD_LABEL="${RD_ID:-<no RD context>}"

HAZARD_FILE="$CZ_ROOT/config/hazard-paths.yaml"
if [ ! -f "$HAZARD_FILE" ]; then
  # Previously a silent `exit 0`. config/hazard-paths.yaml is not written by
  # /cz:init in any project scaffolded before this version, so hazard detection
  # was inert — writes to auth/migration/secret/payment paths escalated
  # nothing, emitted nothing, and triggered no security gate, and that silence
  # was indistinguishable from "no hazard path was touched". Still non-blocking
  # (this hook never denies), but it now says so out loud instead of vanishing.
  cz_log "WARNING: $HAZARD_FILE not found — hazard-path detection is DISABLED for this project. No escalation will be recorded for $FILE_PATH. Copy the plugin's config/hazard-paths.yaml into config/ (or re-run /cz:init) to enable it."
  exit 0
fi

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
  cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":$RD_JSON,\"agent\":\"$AGENT\",\"event\":\"hazard_escalation\",\"result\":\"escalated_to_heavy\",\"error_type\":null}"
  cz_log "HAZARD PATH MATCH ($MATCHED) on $FILE_PATH — $RD_LABEL escalated to profile: heavy for this change. Security review and A+ leash now apply regardless of module_overrides."
  # Non-blocking: escalation, not denial. The gate engine (cz:gate) reads this
  # event and enforces the heavier gate sequence; this hook only records the fact.
fi

exit 0
