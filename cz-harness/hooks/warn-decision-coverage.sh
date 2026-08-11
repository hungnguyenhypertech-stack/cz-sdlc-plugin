#!/usr/bin/env bash
# PostToolUse hook (matcher: Write) — fires after deliverables/RISK-*.md is
# written. Non-blocking advisory only (log + telemetry, never cz_deny) —
# mirrors detect-hazard.sh's pattern. Added per /cz:health-check's
# 2026-08-10 AIBOOTCAMP run's Decision-coverage finding: risk-gov can rate a
# module `hazard: HIGH` with real, detailed rationale (RISK-*.md's own
# prose), but nothing required that rationale to also exist at either of
# this project's two canonical decision-record locations — a dedicated
# `deliverables/adr/*.md` file, or a `#### ADR-NNN` heading inside that
# module's own section of ARCH-*.md — so it stayed reachable only as
# embedded prose, invisible to anyone walking ADRs specifically.
#
# This check mirrors /cz:health-check's own Decision-coverage methodology
# exactly (same two locations, same "does a heading/file exist" test, not a
# stricter content-match) — it is the preventive form of the same read.
#
# Best-effort text scan, not a structured parser: RISK-*.md's hazard rating
# is prose ("### 1.4 `module` — hazard: **HIGH**"), not YAML, consistent
# with every other "dependency-free, best-effort, not a general parser"
# reader in this plugin (see hooks/lib/common.sh's cz_rd_field header).
#
# Known scope limit (deliberate, not a bug): this only checks whether an
# `#### ADR-NNN` heading EXISTS in the module's section — it cannot judge
# whether that ADR is actually ABOUT the hazard rationale. On a real run
# (AIBOOTCAMP), `task-list-view` has ADR-004 in its section, but ADR-004 is
# about state-ownership/update-flow, not the XSS/DOM-safety hazard RISK.md
# actually rates it HIGH for — health-check's own pass caught that mismatch
# only by reading and judging the ADR's prose content, a semantic call this
# grep-based hook cannot safely make (a keyword heuristic here would just
# trade a false negative for a false positive on some other project's
# vocabulary). This hook mechanically catches the cheaper, unambiguous case
# — zero ADR record anywhere for the module (task-authoring's case) — and
# leaves topical-mismatch detection to /cz:health-check's read-only pass.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

[ -n "$FILE_PATH" ] || exit 0
BASENAME="$(basename "$FILE_PATH")"
case "$BASENAME" in
  RISK-*.md) : ;;
  *) exit 0 ;;
esac
[ -f "$FILE_PATH" ] || exit 0

# Project code from the filename itself: RISK-<CODE>.md -> <CODE>. ARCH-*.md
# and deliverables/adr/*.md are looked up relative to this same project.
CODE="${BASENAME#RISK-}"
CODE="${CODE%.md}"
ARCH_FILE="$DELIVERABLES_DIR/ARCH-$CODE.md"
ADR_DIR="$DELIVERABLES_DIR/adr"

# One module name per hazard:**HIGH** heading, e.g. "### 1.4 `task-list-view`
# — hazard: **HIGH**" -> "task-list-view". Modules rated LOW/MEDIUM are out
# of scope for this check (this project's own gate-2 trigger is HIGH only).
HIGH_MODULES="$(grep -oE '^#+[[:space:]]+[0-9.]+[[:space:]]+`[A-Za-z0-9_-]+`.*hazard:[[:space:]]*\*\*HIGH\*\*' "$FILE_PATH" 2>/dev/null \
  | grep -oE '`[A-Za-z0-9_-]+`' | tr -d '`')"
[ -n "$HIGH_MODULES" ] || exit 0

# ANY file under deliverables/adr/*.md satisfies the "dedicated file"
# location for every module (health-check's own check is project-wide here,
# not per-module, since it found zero files at all).
ADR_DIR_HAS_FILES=0
if [ -d "$ADR_DIR" ]; then
  for f in "$ADR_DIR"/*.md; do
    [ -f "$f" ] && ADR_DIR_HAS_FILES=1
    break
  done
fi

while IFS= read -r module; do
  [ -n "$module" ] || continue
  [ "$ADR_DIR_HAS_FILES" -eq 1 ] && continue   # satisfied project-wide, nothing to flag for this module

  # This module's own ARCH-*.md section: from its "## N. `module`" heading
  # up to (not including) the next "## " heading.
  HAS_ADR_HEADING=0
  if [ -f "$ARCH_FILE" ]; then
    SECTION="$(awk -v mod="$module" '
      BEGIN { insec = 0 }
      /^## / {
        if (insec) exit
        if ($0 ~ "`" mod "`") { insec = 1 }
        next
      }
      insec { print }
    ' "$ARCH_FILE")"
    echo "$SECTION" | grep -qE '^#### ADR-[0-9]+' && HAS_ADR_HEADING=1
  fi
  [ "$HAS_ADR_HEADING" -eq 1 ] && continue

  if [ -f "$TELEMETRY_FILE" ] && grep "\"event\":\"decision_gap\"" "$TELEMETRY_FILE" 2>/dev/null \
       | grep -q "\"result\":\"$(cz_json_escape "$module")\""; then
    continue   # already flagged for this module
  fi

  cz_log "DECISION GAP: module '$module' is rated hazard: HIGH in $BASENAME but has no #### ADR-NNN section in ${ARCH_FILE#"$CZ_ROOT"/} and no file under deliverables/adr/*.md. /cz:health-check flags this as a Decision-coverage gap — the rationale exists (RISK.md prose) but not at either canonical decision-record location. See docs/TRACEABILITY.md."
  cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"hook\",\"rd\":null,\"agent\":\"unknown\",\"event\":\"decision_gap\",\"result\":\"$(cz_json_escape "$module")\",\"error_type\":null}"
done <<< "$HIGH_MODULES"

exit 0
