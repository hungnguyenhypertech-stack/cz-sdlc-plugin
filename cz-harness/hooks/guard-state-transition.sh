#!/usr/bin/env bash
# PreToolUse hook — the sole authority for RD-state edits. Rejects any
# transition not present in plan §6.1's table. This makes the state machine
# enforcement, not documentation.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(echo "$HOOK_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"/\1/')"

case "$FILE_PATH" in
  */rd/*.md) : ;;
  *) exit 0 ;;
esac

# NEW_STATE extraction handles two shapes seen in a Write/Edit tool-call
# payload targeting rd/*.md:
#   1. a literal JSON `"state": "value"` pair (defensive — no known caller
#      produces this for an rd/*.md write today, but cheap to keep matching);
#   2. the YAML frontmatter's `state: value` line (unquoted key, often
#      unquoted value), which arrives embedded as an escaped substring inside
#      the payload's "content" (Write) or "new_string" (Edit) field — this is
#      the actual shape every real RD-state write takes, and the previous
#      version of this hook only matched shape 1, so it silently no-op'd on
#      every real transition. "state:" cannot collide with "statement:" (the
#      only other RD field with "state" as a prefix) since a colon never
#      immediately follows "state" inside "statement:". `tail -1` picks the
#      last match so a full-file Write's frontmatter `state:` line wins over
#      any earlier incidental use of the substring in prose (e.g. `notes:`) —
#      still best-effort, not a general YAML/JSON parser, consistent with
#      cz_rd_field's documented tradeoff in hooks/lib/common.sh.
NEW_STATE="$(echo "$HOOK_INPUT" \
  | grep -oE '"state"[[:space:]]*:[[:space:]]*"[^"]*"|state:[[:space:]]*[A-Za-z_]+' \
  | tail -1 \
  | sed -E 's/^"state"[[:space:]]*:[[:space:]]*"(.*)"$/\1/; s/^state:[[:space:]]*//' || true)"
[ -n "$NEW_STATE" ] || exit 0

CURRENT_STATE="$(cz_rd_field "$FILE_PATH" state 2>/dev/null || echo "draft")"
[ "$CURRENT_STATE" = "$NEW_STATE" ] && exit 0

# Table below is the executable mirror of plan §6.1. "*" = any non-terminal from-state.
is_allowed() {
  local from="$1" to="$2"
  case "$from->$to" in
    "draft->ready"|"draft->blocked_dep") return 0 ;;
    "blocked_dep->ready") return 0 ;;
    "ready->claimed") return 0 ;;
    "claimed->red"|"claimed->ready") return 0 ;;
    "claimed->green")
      # Only valid under profile: light AND layer: 1 AND red_skipped:true recorded.
      local profile layer red_skipped
      profile="$(grep -oE 'profile:[[:space:]]*[a-z]+' "$GATES_YAML" 2>/dev/null | awk '{print $2}')"
      layer="$(cz_rd_field "$FILE_PATH" layer 2>/dev/null | tr -d ' ')"
      red_skipped="$(cz_rd_field "$FILE_PATH" red_skipped 2>/dev/null | tr -d ' ')"
      [ "$profile" = "light" ] && [ "$layer" = "1" ] && [ "$red_skipped" = "true" ]
      return $?
      ;;
    "red->green"|"red->red") return 0 ;;
    "green->ai_review") return 0 ;;
    "ai_review->sec_review"|"ai_review->human_review"|"ai_review->rejected") return 0 ;;
    "sec_review->human_review"|"sec_review->rejected") return 0 ;;
    "human_review->accepted"|"human_review->rejected") return 0 ;;
    "rejected->red") return 0 ;;
    "stale->red"|"stale->ready") return 0 ;;
    "blocked_hardstop->"*) return 0 ;;   # returns to prior state or stale; both allowed
    *"->stale") return 0 ;;              # any non-terminal state, normative edit
    *"->blocked_hardstop") return 0 ;;   # any non-terminal state, contradiction detected
    *"->withdrawn") return 0 ;;          # any state, human descope
    "accepted->stale") return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_allowed "$CURRENT_STATE" "$NEW_STATE"; then
  cz_deny "illegal RD transition $CURRENT_STATE -> $NEW_STATE for $FILE_PATH (not in plan §6.1's table)"
fi

# Terminal state: withdrawn has no outbound edges at all.
if [ "$CURRENT_STATE" = "withdrawn" ]; then
  cz_deny "withdrawn is terminal — $FILE_PATH cannot transition out of it"
fi

exit 0
