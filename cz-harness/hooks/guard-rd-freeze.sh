#!/usr/bin/env bash
# PreToolUse hook — fires before any Write/Edit into an RD's source paths.
# Blocks all writes to that RD's src/** while ANY linked test case is stale
# (plan §5.3 step 3). Re-derivation by test-designer + a fresh red log is the
# only way through; it is not bypassable by profile.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

case "$FILE_PATH" in
  */src/*) : ;;
  *) exit 0 ;;
esac

# See guard-red-before-green.sh's comment: prefer the sole active claim lock
# over grepping the TARGET file's own content, since a shared file (one file
# per module) carrying several RDs' annotations would otherwise always
# resolve to whichever RD's annotation appears first, not the one active now.
RD_ID="${CZ_ACTIVE_RD:-}"
[ -n "$RD_ID" ] || RD_ID="$(cz_sole_lock_rd)"
[ -n "$RD_ID" ] || RD_ID="$(grep -oE 'RD-[A-Za-z0-9]+-[0-9]+\.[0-9]+[a-z]?' "$FILE_PATH" 2>/dev/null | head -1 || true)"
[ -n "$RD_ID" ] || exit 0   # nothing to check against; guard-red-before-green already denies untagged writes

RD_PATH="$(cz_rd_path "$RD_ID")"
[ -f "$RD_PATH" ] || exit 0

RD_STATE="$(cz_rd_field "$RD_PATH" state)"
if [ "$RD_STATE" = "stale" ]; then
  cz_deny "$RD_ID is stale — a normative field changed since tests were derived. test-designer must re-derive tests and produce a fresh red log against the new content_hash before any src/** write is allowed. See docs/TRACEABILITY.md (freeze rule)."
fi

RD_HASH="$(cz_rd_field "$RD_PATH" content_hash)"
# Each TC linked in the RD's own `tests:` list (rd-template.yaml) is copied
# per tc-template.yaml as tests/.meta/<tc-id>.yaml and carries its own
# rd_hash: field — the hash of the RD at the moment it was derived. Compare
# that directly to the RD's CURRENT content_hash; no separate sidecar file
# exists or needs to (a prior version of this hook looked for
# tests/.meta/*.rdhash sidecars that nothing else in the plugin ever wrote,
# so this check never fired in practice — see audit finding C4).
TC_DIR="$CZ_ROOT/tests/.meta"
if [ -d "$TC_DIR" ]; then
  while IFS= read -r tc_id; do
    [ -n "$tc_id" ] || continue
    TC_FILE="$TC_DIR/$tc_id.yaml"
    [ -f "$TC_FILE" ] || continue   # not yet derived — an RTM orphan concern (§5.4), not a freeze concern
    TC_HASH="$(cz_rd_field "$TC_FILE" rd_hash)"
    if [ -n "$TC_HASH" ] && [ "$TC_HASH" != "$RD_HASH" ]; then
      cz_deny "test case $tc_id (linked to $RD_ID via its tests: list) is stale — recorded rd_hash $TC_HASH != current $RD_HASH. test-designer must re-derive it and produce a fresh red log before any src/** write is allowed. See docs/TRACEABILITY.md (freeze rule)."
    fi
  done < <(cz_rd_tests_list "$RD_PATH")
fi

exit 0
