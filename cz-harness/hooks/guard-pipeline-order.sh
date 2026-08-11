#!/usr/bin/env bash
# PreToolUse hook — enforces plan §8.2's outer-pipeline ordering rule at the
# tool layer: "Step n+1 is refused until step n has a passed gate record and
# an answered Understanding Gate." Audit finding M4: every commands/cz-*.md
# pipeline-step file already documents this as a prose "Gate check: refuse
# unless gate-records/PB<n>-*.json status:passed" instruction, but nothing
# mechanically enforced it — unlike the RD-level sub-flow, where
# guard-state-transition.sh genuinely enforces the transition table at the
# hook layer. This hook mirrors that same pattern for the outer pipeline's
# once-per-project phase gates (steps 0-6, 10) and the per-RD gates (steps
# 7-9), reading the exact step ordering from the command files themselves
# (see the "Gate check" line in each commands/cz-*.md) rather than
# reinventing it.
#
# Understanding Gate answers are NOT checked here (that's a human-authored
# free-text field, not something a Write/Edit hook on a *different* file can
# usefully gate on) — this hook only enforces the "prior gate record has
# status:passed" half of the rule, same scope as the fix direction in the
# audit (M4's evidence cites exactly this gap).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
FILE_PATH="$(cz_json_str_field file_path "$HOOK_INPUT")"

[ -n "$FILE_PATH" ] || exit 0

# Only pipeline-artifact writes under deliverables/** are in scope; anything
# else (src/**, tests/**, rd/**, gate-records/** itself, ...) is untouched by
# this hook — those already have their own guards (guard-red-before-green,
# guard-state-transition, guard-role-boundaries, ...).
case "$FILE_PATH" in
  */deliverables/*.md) : ;;
  *) exit 0 ;;
esac

BASENAME="$(basename "$FILE_PATH")"

# cz_phase_gate_passed <gate-records-filename>: true if a phase-level (i.e.
# once-per-project, steps 0-6/10) gate record exists with "status":"passed".
# This is the shape every real PB<n>-*.json record uses in production (see
# gate-records/PB0-scope.json, PB1-spec.json, ... in a real cz-harness
# project). Audit finding N5 (2026-07-29, resolved): schemas/gate-record.schema.json
# used to describe a different, richer shape (gate_id/rd/gate_type/verdict/...)
# that nothing in the outer pipeline ever wrote; it has since been reconciled
# to describe this flat shape (and the RD-level dor/gate shapes) directly, so
# this check and the schema now agree.
cz_phase_gate_passed() {
  local f="$GATE_RECORDS_DIR/$1"
  [ -f "$f" ] && grep -q '"status"[[:space:]]*:[[:space:]]*"passed"' "$f"
}

# cz_rd_dor_passed <rd-id>: true if this RD's own per-RD DoR gate record
# (gate-records/<rd-id>-dor.json, e.g. RD-AIBOOTCAMP-002.01a-dor.json) exists
# with "status":"passed". Steps 7-9 are evaluated per RD, not once per
# project (plan §4.3) — this must NEVER be confused with cz_phase_gate_passed
# above, which only ever reads once-per-project PB<n>-*.json records.
cz_rd_dor_passed() {
  local rd="$1"
  local f="$GATE_RECORDS_DIR/${rd}-dor.json"
  [ -f "$f" ] && grep -q '"status"[[:space:]]*:[[:space:]]*"passed"' "$f"
}

# cz_any_rd_gate_approved: true if ANY gate-records/*-gate.json anywhere in
# the project has gate_decision.decision == "approved". cz-report.md's own
# gate check ("refuse unless at least one RD has a passed
# gate-records/<rd-id>-gate.json this reporting period") is project-wide —
# it does not name one specific RD — so this scans every *-gate.json rather
# than looking up a single RD id.
cz_any_rd_gate_approved() {
  local f
  [ -d "$GATE_RECORDS_DIR" ] || return 1
  for f in "$GATE_RECORDS_DIR"/*-gate.json; do
    [ -f "$f" ] || continue
    grep -q '"decision"[[:space:]]*:[[:space:]]*"approved"' "$f" && return 0
  done
  return 1
}

case "$BASENAME" in
  SCOPE-*.md)
    # Step 0 (/cz:scope) has no predecessor — never blocked (plan §8.2).
    exit 0
    ;;
  SPEC-*.md)
    # Step 1 predecessor: step 0 (cz-scope.md's own exit condition).
    cz_phase_gate_passed "PB0-scope.json" || \
      cz_deny "step 1 (/cz:spec) refused: gate-records/PB0-scope.json is not status:passed yet (plan §8.2 outer pipeline — step n+1 requires step n's passed gate record)"
    ;;
  MODULEMAP-*.md)
    # Step 2 predecessor: step 1 (cz-modulemap.md's own "Gate check" line).
    cz_phase_gate_passed "PB1-spec.json" || \
      cz_deny "step 2 (/cz:modulemap) refused: gate-records/PB1-spec.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  ARCH-*.md)
    # Step 3 predecessor: step 2 (cz-arch.md's own "Gate check" line).
    cz_phase_gate_passed "PB2-modulemap.json" || \
      cz_deny "step 3 (/cz:arch) refused: gate-records/PB2-modulemap.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  WBS-*.md)
    # Step 4 predecessor: step 3 (cz-wbs.md's own "Gate check" line).
    cz_phase_gate_passed "PB3-arch.json" || \
      cz_deny "step 4 (/cz:wbs) refused: gate-records/PB3-arch.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  EST-*.md)
    # Step 5 predecessor: step 4 (cz-estimate.md's own "Gate check" line).
    cz_phase_gate_passed "PB4-wbs.json" || \
      cz_deny "step 5 (/cz:estimate) refused: gate-records/PB4-wbs.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  RISK-*.md|DELEGATION-MAP-*.md)
    # Step 6 predecessor: step 5 (cz-risk.md's own "Gate check" line). RISK
    # and DELEGATION-MAP are the two outputs of the SAME step 6, so they
    # share the same predecessor gate.
    cz_phase_gate_passed "PB5-estimate.json" || \
      cz_deny "step 6 (/cz:risk) refused: gate-records/PB5-estimate.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  DOR-*.md)
    # Step 7 (/cz:dor) is per-RD (plan §4.3), but its IMMEDIATE predecessor
    # is still step 6, a once-per-project phase gate (cz-dor.md's own "Gate
    # check" line: "refuse unless gate-records/PB6-risk.json is status
    # passed..."). Deliberately checking the phase gate only here, never a
    # per-RD one, so per-RD DOR writes aren't conflated with the phase gates
    # (see this hook's header comment and the RD-level cz_rd_dor_passed
    # check below, used only for the DEVBOOK case).
    cz_phase_gate_passed "PB6-risk.json" || \
      cz_deny "step 7 (/cz:dor) refused: gate-records/PB6-risk.json is not status:passed yet (plan §8.2 outer pipeline)"
    ;;
  DEVBOOK-*.md)
    # Step 8 (/cz:build) is per-RD; its immediate predecessor is THIS SAME
    # RD's own DoR gate record (cz-build.md's own "Gate check" line:
    # "refuse unless gate-records/<rd-id>-dor.json is status:passed"), not a
    # phase-level record — steps 7-9 are evaluated per RD, not once per
    # project (plan §4.3). Extract the RD id from the DEVBOOK-<rd-id>.md
    # filename to know which per-RD gate record to look up.
    RD_ID="$(cz_extract_rd_id "$FILE_PATH")"
    if [ -z "$RD_ID" ]; then
      cz_deny "step 8 (/cz:build) refused: could not determine an RD id from $FILE_PATH to look up its DoR gate record (expected deliverables/DEVBOOK-<rd-id>.md)"
    fi
    cz_rd_dor_passed "$RD_ID" || \
      cz_deny "step 8 (/cz:build) refused: gate-records/${RD_ID}-dor.json is not status:passed yet for $RD_ID (plan §8.2 outer pipeline)"
    ;;
  RTM-*.md|WEEKLY-*.md|CASE-STUDY.md)
    # Step 10 (/cz:report) predecessor per cz-report.md's own "Gate check"
    # line: "refuse unless at least one RD has a passed
    # gate-records/<rd-id>-gate.json this reporting period" — project-wide
    # (any RD), not tied to one specific RD id.
    cz_any_rd_gate_approved || \
      cz_deny "step 10 (/cz:report) refused: no gate-records/*-gate.json with gate_decision.decision:\"approved\" exists yet (plan §8.2 outer pipeline — /cz:report needs at least one delivered RD this period)"
    ;;
  *)
    # Any other deliverables/**/*.md (reviews/**, understanding-log/**,
    # coverage/**, adr/**, UNDERSTANDING-LOG.md, ...) is out of scope for
    # this hook — it only guards the named outer-pipeline artifacts above.
    exit 0
    ;;
esac

exit 0
