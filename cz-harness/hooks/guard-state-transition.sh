#!/usr/bin/env bash
# PreToolUse hook — the sole authority for RD-state edits. Rejects any
# transition not present in plan §6.1's table. This makes the state machine
# enforcement, not documentation.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

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
      # profile is the RD's OWN effective profile (cz_effective_profile: RD-level
      # override if set, else project gates.yaml) — an RD-level profile:light
      # override is exactly what should unlock this skip, not just a
      # project-wide light profile.
      local profile layer red_skipped
      profile="$(cz_effective_profile "$FILE_PATH")"
      layer="$(cz_rd_field "$FILE_PATH" layer 2>/dev/null | tr -d ' ')"
      red_skipped="$(cz_rd_field "$FILE_PATH" red_skipped 2>/dev/null | tr -d ' ')"
      [ "$profile" = "light" ] && [ "$layer" = "1" ] && [ "$red_skipped" = "true" ]
      return $?
      ;;
    "red->green"|"red->red") return 0 ;;
    "green->ai_review")
      # Step 9 (test-designer's post-implementation AC/TC coverage
      # re-verification) must produce deliverables/coverage/<rd-id>.md before
      # gate 1 can begin. agents/test-designer.md already documents this as
      # its step-9 deliverable output in prose, but nothing enforced it — a
      # real 41-RD project (/cz:health-check, 2026-08-10) had ZERO files
      # under deliverables/coverage/ despite test-designer's own tool grant
      # including Write(deliverables/coverage/*.md); the Retrieval-quality
      # dimension flagged it as a standing gap with no owning mechanism.
      # Denies with its own specific message (rather than falling through to
      # the generic "not in plan §6.1's table" message below, which would be
      # misleading here — this transition IS in the table, it's this one
      # precondition that's unmet) — same rationale as claimed->green above,
      # which has the same generic-message imprecision but is left as-is
      # since it's out of this change's scope.
      local rd_id coverage_file
      rd_id="$(basename "$FILE_PATH" .md)"
      coverage_file="$DELIVERABLES_DIR/coverage/$rd_id.md"
      if [ ! -f "$coverage_file" ]; then
        cz_deny "green->ai_review refused for $rd_id: deliverables/coverage/$rd_id.md does not exist yet. Step 9 (test-designer's post-implementation coverage re-verification) must write this deliverable before gate 1 can begin. See agents/test-designer.md and docs/TRACEABILITY.md."
      fi

      # Smoke check (1.0.26): if the project has opted in to config/gates.yaml's
      # smoke_check.command (its "does the whole thing actually run" check, not
      # just this RD's unit tests), cz-build.md step 9a must have produced
      # evidence/RD-<id>/smoke-*.log before gate 1 begins — same mechanical
      # pattern as the coverage file above. Absent smoke_check.command entirely
      # = project hasn't defined one = no-op, do not block. Under profile:light
      # for this RD, missing evidence is a warning on stderr, not a block —
      # same light-profile leniency precedent as the red-skip case above.
      local smoke_cmd smoke_glob smoke_profile
      smoke_cmd="$(awk '
        /^smoke_check:/ { inblock=1; next }
        inblock && /^[^ \t]/ { inblock=0 }
        inblock && /^[ \t]+command:/ { v=$0; sub(/^[ \t]+command:[ \t]*/, "", v); print v; exit }
      ' "$GATES_YAML" 2>/dev/null || true)"
      if [ -n "$smoke_cmd" ]; then
        smoke_glob="$EVIDENCE_DIR/RD-$rd_id/smoke-"*.log
        # shellcheck disable=SC2144
        if [ ! -f $smoke_glob ] 2>/dev/null; then
          smoke_profile="$(cz_effective_profile "$FILE_PATH")"
          if [ "$smoke_profile" = "light" ]; then
            echo "[cz-harness] WARN: $rd_id has no evidence/RD-$rd_id/smoke-*.log yet (smoke_check.command is configured); allowed to proceed under profile:light, but should still be run. See commands/cz-build.md step 9a." >&2
          else
            cz_deny "green->ai_review refused for $rd_id: config/gates.yaml defines smoke_check.command but no evidence/RD-$rd_id/smoke-*.log exists. cz-build.md step 9a must run the smoke check before gate 1 can begin under profile:$smoke_profile."
          fi
        fi
      fi
      return 0
      ;;
    "ai_review->sec_review"|"ai_review->human_review"|"ai_review->rejected") return 0 ;;
    "sec_review->human_review"|"sec_review->rejected") return 0 ;;
    "human_review->accepted"|"human_review->rejected") return 0 ;;
    "rejected->red") return 0 ;;
    "stale->red"|"stale->ready") return 0 ;;
    "blocked_hardstop->"*) return 0 ;;   # returns to prior state or stale; both allowed
    *"->stale") return 0 ;;              # any non-terminal state, normative edit
    *"->blocked_hardstop") return 0 ;;   # any non-terminal state, contradiction detected
    *"->withdrawn") return 0 ;;          # any state, human descope (dropped, no successor)
    *"->superseded") return 0 ;;         # any state, replaced by a successor RD (e.g. a
                                          # /cz:rd split) — real RDs use this state
                                          # (schemas/rd.schema.json, docs/TRACEABILITY.md)
                                          # but it was missing from this table, meaning
                                          # every such transition predates this guard or
                                          # bypassed it; added so it's actually enforced.
    "accepted->stale") return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_allowed "$CURRENT_STATE" "$NEW_STATE"; then
  cz_deny "illegal RD transition $CURRENT_STATE -> $NEW_STATE for $FILE_PATH (not in plan §6.1's table)"
fi

# Terminal states: withdrawn and superseded have no outbound edges at all.
if [ "$CURRENT_STATE" = "withdrawn" ] || [ "$CURRENT_STATE" = "superseded" ]; then
  cz_deny "$CURRENT_STATE is terminal — $FILE_PATH cannot transition out of it"
fi

exit 0
