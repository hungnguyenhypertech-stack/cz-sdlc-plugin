#!/usr/bin/env bash
# PreToolUse hook — fires before any Write/Edit into src/**.
# Blocks the write unless the current RD has a red log matching its current
# content_hash and recording a REAL failure (plan §5.3, §6.1, §8.3).
#
# Input: Claude Code hook JSON on stdin, containing at least
#   { "tool_input": { "file_path": "<abs path>" }, "cwd": "<project root>" }
# Exit 0 = allow. Exit 1 (+ stderr) = deny, tool call is blocked.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/test-runner-adapter.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

# Only src/** writes are in scope for this guard.
case "$FILE_PATH" in
  */src/*) : ;;
  *) exit 0 ;;
esac

# Which RD owns this write? dev must annotate the file with "# RD-<id>" (plan §8.3).
# On a brand-new file there is no annotation yet — the RD must be supplied via
# CZ_ACTIVE_RD (set by /cz:build for the duration of the claimed session), but
# that env var is rarely actually set (see lib/common.sh's "Identity
# fallback"). Prefer the sole active claim lock over grepping the TARGET
# file's own content: a shared file (one file per module, per ARCH's
# convention — e.g. src/task-model.mjs carrying annotations for several RDs)
# would otherwise always resolve to whichever RD's annotation happens to
# appear FIRST in the file, not the RD actually being worked on right now.
# Only fall back to the file-content grep as a last resort (e.g. no active
# lock exists at all, such as a manual/direct edit outside a claimed loop).
RD_ID="${CZ_ACTIVE_RD:-}"
[ -n "$RD_ID" ] || RD_ID="$(cz_sole_lock_rd)"

# Under bounded/wave concurrency (>1 claim held) cz_sole_lock_rd returns ""
# by construction, and the on-disk grep below cannot help for a file that does
# not exist yet — so a brand-new src/** file was denied outright with "claim an
# RD via /cz:build first" even though the RD *was* claimed and the incoming
# content *did* carry its `# RD-<id>` annotation. That made two of the three
# concurrency modes /cz:init offers unusable for new code.
#
# Resolve from the INCOMING content instead (the write hasn't landed yet, so
# this is the only place that annotation exists), and disambiguate the
# shared-file case this guard's header warns about by intersecting against the
# set of RDs actually claimed right now: an annotation naming an RD nobody
# holds is not the RD being worked on. Only an unambiguous single match is
# accepted — anything else falls through to the pre-existing behavior.
if [ -z "$RD_ID" ]; then
  CONTENT="$(echo "$HOOK_INPUT" \
    | grep -oE '"(content|new_string)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
    | head -1 || true)"
  CANDIDATES="$(echo "$CONTENT" | grep -oE 'RD-[A-Za-z0-9]+-[0-9]+\.[0-9]+[a-z]?' | sort -u || true)"
  if [ -n "$CANDIDATES" ]; then
    LOCKED="$(cz_locked_rd_ids)"
    MATCHES=""
    if [ -n "$LOCKED" ]; then
      MATCHES="$(echo "$CANDIDATES" | grep -Fxf <(echo "$LOCKED") || true)"
    fi
    if [ "$(echo "$MATCHES" | grep -c .)" -eq 1 ]; then
      RD_ID="$(echo "$MATCHES" | head -1)"
      cz_log "resolved $RD_ID from the incoming write's own RD annotation (>1 claim held, so sole-lock resolution was unavailable)"
    fi
  fi
fi

if [ -z "$RD_ID" ] && [ -f "$FILE_PATH" ]; then
  RD_ID="$(grep -oE 'RD-[A-Za-z0-9]+-[0-9]+\.[0-9]+[a-z]?' "$FILE_PATH" | head -1 || true)"
fi
[ -n "$RD_ID" ] || cz_deny "no active RD context for write to $FILE_PATH — annotate the file with '# RD-<id>' for one of the currently-claimed RDs ($(cz_locked_rd_ids | paste -sd, - || echo 'none claimed')), or claim an RD via /cz:build first"

RD_PATH="$(cz_rd_path "$RD_ID")"
[ -f "$RD_PATH" ] || cz_deny "RD record not found: $RD_PATH"

RD_STATE="$(cz_rd_field "$RD_PATH" state)"
RD_HASH="$(cz_rd_field "$RD_PATH" content_hash)"
RD_HASH="${RD_HASH%\"}"; RD_HASH="${RD_HASH#\"}"
RED_LOG="$(cz_rd_field "$RD_PATH" evidence.red_log 2>/dev/null || true)"
# fallback: nested YAML — evidence.red_log is not a flat top-level key, so read it
# from the conventional path if the flat read comes back empty.
[ -z "${RED_LOG:-}" ] && RED_LOG="$EVIDENCE_DIR/$RD_ID/tests-red-$(cz_rd_field "$RD_PATH" version | tr -d ' ').log"
# rd-template.yaml's evidence.red_log is documented and written as a path
# relative to CZ_ROOT (e.g. "evidence/RD-.../tests-red-v3.log"), but a bare
# `[ -f "$RED_LOG" ]` resolves a relative path against the CALLING process's
# cwd, not CZ_ROOT — those only coincide by accident. Always anchor to
# CZ_ROOT explicitly unless the field already held an absolute path (audit
# finding M1: the "should-pass" case — a genuinely valid, matching red log —
# was the one that incorrectly denied when cwd != CZ_ROOT).
case "$RED_LOG" in
  /*) : ;;
  *) RED_LOG="$CZ_ROOT/$RED_LOG" ;;
esac

if [ "$RD_STATE" = "green" ] || [ "$RD_STATE" = "ai_review" ] || [ "$RD_STATE" = "sec_review" ] || [ "$RD_STATE" = "human_review" ] || [ "$RD_STATE" = "accepted" ]; then
  # Refactor / post-green edits: require the SAME red log still exists (it must,
  # tests are byte-identical to the red run per plan §6.1) — allow.
  [ -f "$RED_LOG" ] || cz_deny "$RD_ID is $RD_STATE but its red log is missing — refactor edits require an intact red proof"
  exit 0
fi

if [ "$RD_STATE" != "claimed" ] && [ "$RD_STATE" != "red" ]; then
  cz_deny "$RD_ID is in state '$RD_STATE' — src/** may only be written while claimed or red (or green+ during refactor)"
fi

# Light-profile red-skip: all three conditions must hold simultaneously —
# profile:light AND layer:1 AND red_skipped:true on this RD. Mirrors the
# identical three-condition check in guard-state-transition.sh's claimed->green
# gate; neither check can be loosened without also loosening the other.
_profile="$(grep -m1 -oE '^profile:[[:space:]]*[a-z]+' "$GATES_YAML" 2>/dev/null | sed -E 's/^profile:[[:space:]]*//' || true)"
if [ "$_profile" = "light" ]; then
  _layer="$(cz_rd_field "$RD_PATH" layer | tr -d ' ')"
  _red_skipped="$(cz_rd_field "$RD_PATH" red_skipped | tr -d ' ')"
  if [ "$_layer" = "1" ] && [ "$_red_skipped" = "true" ]; then
    exit 0
  fi
fi

[ -f "$RED_LOG" ] || cz_deny "no red log at $RED_LOG for $RD_ID — test-designer must produce a proven-failing run before dev writes code (RD not skippable: see docs/LIGHTWEIGHT-MODE.md for the one named exception)"

grep -q "$RD_HASH" "$RED_LOG" || cz_deny "red log at $RED_LOG does not match current content_hash $RD_HASH for $RD_ID — RD changed since red was proven; re-derive tests first"

cz_tests_all_failed "$RED_LOG" || cz_deny "red log at $RED_LOG does not record a real failure (e.g. a collection/import error masquerading as red is not red proof)"

exit 0
