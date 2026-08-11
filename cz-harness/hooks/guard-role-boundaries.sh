#!/usr/bin/env bash
# PreToolUse hook — enforces the anti-collusion invariants of plan §8.1 at the
# tool layer, not by instruction. Runs for every Write/Edit and for the specific
# "set human_approved" write path.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"
CONTENT="$(cz_json_unescape "$(cz_json_str_field content "$HOOK_INPUT")")"

# Scratch file for the telemetry append-only check below (M3 audit fix). Kept
# at top-level scope (not inside the case arm) so a single EXIT trap can
# clean it up regardless of which path out of this script is taken —
# cz_deny() calls `exit 1` directly, which would skip any cleanup written
# after it inline.
TELEMETRY_NEW_TMP=""
cleanup_telemetry_tmp() { [ -n "$TELEMETRY_NEW_TMP" ] && rm -f "$TELEMETRY_NEW_TMP"; return 0; }
trap cleanup_telemetry_tmp EXIT

# CZ_ACTING_AGENT is meant to be set by the command/agent runtime, but no
# command or agent definition actually exports it (env vars also can't
# survive across Bash tool calls or into a Task-dispatched subagent) — fall
# back to disk. Prefer the lock for the RD this specific write belongs to
# (correct even with several RDs claimed at once); only fall back to the
# ambiguous sole-lock guess if no RD id appears anywhere in this call, and
# finally to "human" for direct user edits. See lib/common.sh's "Identity
# fallback" section.
ACTOR="${CZ_ACTING_AGENT:-}"
if [ -z "$ACTOR" ]; then
  RD_FOR_ACTOR="$(cz_extract_rd_id "$HOOK_INPUT")"
  if [ -n "$RD_FOR_ACTOR" ]; then
    ACTOR="$(cz_lock_agent_for_rd "$RD_FOR_ACTOR")"
  fi
fi
[ -n "$ACTOR" ] || ACTOR="$(cz_sole_lock_agent)"
ACTOR="${ACTOR:-human}"

deny_if() { [ "$1" = "1" ] && cz_deny "$2" || true; }

case "$FILE_PATH" in
  */tests/*)
    [ "$ACTOR" = "dev" ] && cz_deny "dev may not write to tests/** — dev↛tests is an anti-collusion invariant, not a preference"
    ;;
  */src/*)
    [ "$ACTOR" = "test-designer" ] && cz_deny "test-designer may not write to src/** — test-designer↛src is an anti-collusion invariant"
    ;;
  */reviews/*)
    [ "$ACTOR" != "ai-reviewer" ] && [ "$ACTOR" != "sec-reviewer" ] && [ "$ACTOR" != "human" ] && \
      cz_deny "only ai-reviewer/sec-reviewer/human may write under reviews/**"
    ;;
  */gate-records/*)
    if echo "$CONTENT" | grep -q '"human_approved"[[:space:]]*:[[:space:]]*true'; then
      if [ "$ACTOR" != "human" ]; then
        # "rd" here reuses RD_FOR_ACTOR (already resolved above via
        # cz_extract_rd_id against this same tool call) when the forged write
        # named a real RD — gate-records/<rd-id>-gate.json's own filename
        # almost always does. Real JSON null (not the string "unknown", which
        # violates telemetry-event.schema.json's rd pattern) is the honest
        # fallback on the rare call where no RD id is resolvable at all.
        RD_FOR_EVENT_JSON="null"
        [ -n "${RD_FOR_ACTOR:-}" ] && RD_FOR_EVENT_JSON="\"$RD_FOR_ACTOR\""
        cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":$RD_FOR_EVENT_JSON,\"agent\":\"$ACTOR\",\"event\":\"agent_error\",\"error_type\":\"permission_denied\",\"result\":\"blocked_human_approved_forgery\"}"
        cz_deny "only a human may set human_approved: true. Attempt by '$ACTOR' blocked and logged as a governance event (plan §8.1 invariant 4)."
      fi
    fi
    ;;
  */config/gates.yaml)
    [ "$ACTOR" != "human" ] && cz_deny "gates.yaml may only be committed by a human. risk-gov may PROPOSE a change (write to a *.proposed.yaml file) but never commit gates.yaml directly."
    ;;
  */telemetry/events.jsonl)
    [ "$ACTOR" != "agentops" ] && [ "$ACTOR" != "hook" ] && cz_deny "telemetry/events.jsonl is written only by hooks/agentops, and only by append. Direct edits are blocked."

    # --- M3 audit fix: WHO may write is necessary but not sufficient ---------
    # The check above only gates WHO may write telemetry/events.jsonl; it says
    # nothing about WHETHER the write is actually append-only. Without this,
    # agentops itself (granted Write(telemetry/**) by its agent definition)
    # could truncate or rewrite telemetry history via a direct Write tool
    # call, and nothing would stop it — the "telemetry history is immutable"
    # guarantee (plan §8.1 anti-collusion invariant 5; Thesis §1.2: "enforced
    # by tool permissions, not instruction") would rest entirely on
    # agentops.md's prose. This makes it a mechanism: the file's CURRENT
    # on-disk bytes (still the pre-write OLD content — PreToolUse fires
    # BEFORE the tool executes, so disk still holds the old version) must be
    # a strict byte-for-byte prefix of the NEW content this call would write.
    #
    # Deliberately NOT relevant to cz_emit_event() in lib/common.sh: that
    # function appends via plain `>>` shell redirection from WITHIN another
    # hook's own process — it never goes through Claude Code's tool-call
    # layer at all (no Write/Edit tool_input is ever constructed for it), so
    # this PreToolUse hook never even fires for it and there is nothing here
    # that could interfere with those legitimate internal appends. This check
    # exists solely to stop an AGENT's own Write/Edit tool call from
    # truncating telemetry, which is the actual gap M3 identified.
    #
    # Only the Write tool shape is verifiable cheaply (a full "content"
    # field to diff against disk). An Edit-shaped call (old_string/new_string)
    # has no "content" field to check against, and reconstructing a valid
    # verification would require replaying the substitution — not attempted
    # here; Edit-shaped writes to telemetry are blocked outright, since
    # agentops's tool grant is Write(telemetry/**) only (no Edit), so a
    # legitimate telemetry write is never Edit-shaped in the first place.
    CONTENT_RAW_TEL="$(echo "$HOOK_INPUT" | grep -oE '"content"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"' | head -1 || true)"
    if [ -n "$CONTENT_RAW_TEL" ]; then
      CONTENT_BODY_TEL="$(printf '%s' "$CONTENT_RAW_TEL" | sed -E 's/^"content"[[:space:]]*:[[:space:]]*"//; s/"$//')"
      TELEMETRY_NEW_TMP="$(mktemp "${TMPDIR:-/tmp}/cz-telemetry-new.XXXXXX")"
      cz_json_unescape "$CONTENT_BODY_TEL" > "$TELEMETRY_NEW_TMP"

      if [ -f "$FILE_PATH" ]; then
        OLD_SIZE_TEL="$(wc -c < "$FILE_PATH" | tr -d ' ')"
        NEW_SIZE_TEL="$(wc -c < "$TELEMETRY_NEW_TMP" | tr -d ' ')"
        if [ "$NEW_SIZE_TEL" -lt "$OLD_SIZE_TEL" ]; then
          cz_deny "telemetry/events.jsonl write would shrink the file ($OLD_SIZE_TEL -> $NEW_SIZE_TEL bytes) — not an append. telemetry history is immutable (plan §8.1 invariant 5)."
        fi
        if ! head -c "$OLD_SIZE_TEL" "$TELEMETRY_NEW_TMP" | cmp -s - "$FILE_PATH"; then
          cz_deny "telemetry/events.jsonl write is not a strict append — the existing file's content is not a byte-for-byte prefix of the new content (something in the old content was changed or removed). telemetry history is immutable (plan §8.1 invariant 5, Thesis §1.2: enforced by tool permissions, not instruction)."
        fi
      fi
      # else: file doesn't exist yet — first write, any content is fine.
    elif echo "$HOOK_INPUT" | grep -q '"new_string"[[:space:]]*:[[:space:]]*"'; then
      cz_deny "telemetry/events.jsonl append-only check cannot verify an Edit-shaped write (no content field to diff against disk) — blocked out of caution. agentops's tool grant is Write(telemetry/**) only; use a full Write whose content is the existing file plus appended line(s)."
    fi
    ;;
esac

# sub-pm has no approval verb, ever — belt-and-suspenders on top of the gate-records case above.
if [ "$ACTOR" = "sub-pm" ] && echo "$CONTENT" | grep -qi 'approved.*true'; then
  cz_deny "sub-pm has no approval verb — this is enforced even if the write target isn't gate-records/**"
fi

exit 0
