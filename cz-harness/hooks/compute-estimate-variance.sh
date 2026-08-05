#!/usr/bin/env bash
# Callable directly (like guard-claim-lock.sh / restamp-lock.sh / release-lock.sh
# — see their header comments; none of these four are wired into hooks.json as
# a PreToolUse/PostToolUse matcher). Invoked by /cz:gate step 8, only on the
# "approved" branch, right before release-lock.sh — computes how far the RD's
# actual build time diverged from planner's pre-build estimate (rd/*.md's
# estimate.expected_h / .optimistic / .pessimistic), and prints one JSON
# object on stdout for the caller to embed into gate-records/<rd-id>-gate.json
# as the "estimate_variance" field.
#
# Reports both actual_h (raw wall-clock span, first-to-last telemetry
# timestamp for this rd) and active_h (same span with idle/blocked gaps
# longer than IDLE_GAP_THRESHOLD_S excluded — see below). variance_pct and
# within_pessimistic_bound are computed against active_h, not actual_h: an
# RD estimate is a work-effort guess, not a promise about how long it sits
# queued behind max_in_flight or waiting on a human gate, so comparing
# estimate to wall-clock time systematically and misleadingly inflates every
# variance. actual_h is kept in the record for anyone who wants the raw span
# anyway (e.g. throughput reporting, not estimation accuracy).
#
# Deliberately time-only. An earlier design considered threading a token
# estimate/actual through this same path, but Claude Code hooks have no real
# source for per-RD token usage (see emit-telemetry.sh's cost_usd comment:
# "there is no real source for these here, full stop" — same constraint
# applies to tokens). Rather than fabricate a number, this script only ever
# reports what's mechanically derivable today: wall-clock time from
# telemetry's own timestamps. If a real token/cost source (an API-gateway
# wrapper, matching emit-telemetry.sh's CZ_LAST_COST_USD extension point)
# exists later, extend this script then — not before, per this plugin's
# "honest zero, not a silent schema gap" convention.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

RD_ID="${1:-}"
[ -n "$RD_ID" ] || cz_deny "compute-estimate-variance requires an RD id"

RD_FILE="$(cz_rd_path "$RD_ID")"
[ -f "$RD_FILE" ] || cz_deny "compute-estimate-variance: no rd/$RD_ID.md found"

EXPECTED_H="$(cz_rd_field "$RD_FILE" estimate.expected_h | tr -d ' ')"
OPTIMISTIC_H="$(cz_rd_field "$RD_FILE" estimate.optimistic | tr -d ' ')"
PESSIMISTIC_H="$(cz_rd_field "$RD_FILE" estimate.pessimistic | tr -d ' ')"

if [ -z "$EXPECTED_H" ]; then
  # No estimate on record (should not happen — rd.schema.json requires
  # `estimate`, but this script must never crash the accept path over a
  # malformed/legacy RD file) — emit an honest null result rather than deny.
  echo "{\"rd_id\":\"$RD_ID\",\"estimated_h\":null,\"actual_h\":null,\"variance_pct\":null,\"within_pessimistic_bound\":null,\"note\":\"no estimate.expected_h on record\"}"
  exit 0
fi

# Actual wall-clock time: earliest -> latest telemetry timestamp seen for
# this RD (first rd_claim through now, the moment this script runs during
# accept — the true end of the RD's build lifecycle). Deliberately not
# restricted to rd_claim/rd_release only: an RD's real first touch is
# sometimes an earlier agent_dispatch/rd_state_change under the same rd id
# (e.g. dor/build handoff events before the first claim lock in some
# profiles), and the min/max of ALL of this RD's events is the honest
# lifecycle span rather than a narrower, possibly-wrong assumption about
# which two event types bookend it.
if [ ! -f "$TELEMETRY_FILE" ]; then
  echo "{\"rd_id\":\"$RD_ID\",\"estimated_h\":$EXPECTED_H,\"actual_h\":null,\"variance_pct\":null,\"within_pessimistic_bound\":null,\"note\":\"no telemetry file found\"}"
  exit 0
fi

# IDLE_GAP_THRESHOLD_S: a gap between two consecutive telemetry events for
# this RD longer than this is treated as idle/blocked time (waiting on a
# human, queued behind another RD under max_in_flight, overnight, ...), not
# active work — reuses guard-claim-lock.sh's LOCK_TTL_S (1800s) rather than
# inventing a second, competing definition of "no longer actively held": a
# gap past the same TTL that would let another agent reclaim this RD's lock
# is, by the plugin's own existing definition, no longer active work on it.
# Overridable via CZ_IDLE_GAP_THRESHOLD_S for a project that wants a
# different cutoff (e.g. a heavy-profile project with long human-review
# waits baked in as expected, not idle).
IDLE_GAP_THRESHOLD_S="${CZ_IDLE_GAP_THRESHOLD_S:-1800}"

ALL_TS="$(grep -F "\"rd\":\"$RD_ID\"" "$TELEMETRY_FILE" \
  | grep -o '"ts"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed -E 's/.*:"(.*)"/\1/' \
  | sort -u)"

if [ -z "$ALL_TS" ]; then
  echo "{\"rd_id\":\"$RD_ID\",\"estimated_h\":$EXPECTED_H,\"actual_h\":null,\"active_h\":null,\"idle_h\":null,\"variance_pct\":null,\"within_pessimistic_bound\":null,\"note\":\"no telemetry events found for this rd\"}"
  exit 0
fi

# Convert every timestamp to epoch seconds up front (BSD/macOS and GNU date
# take different flags — same fallback pattern used elsewhere in this repo),
# then let one awk pass do the wall-clock span AND the active/idle split
# (sum of consecutive gaps <=/> threshold) in a single walk over the sorted
# epoch list, so "actual" and "active" are always computed from the exact
# same event set — never two separately-derived numbers that could drift
# apart from each other.
EPOCHS="$(while IFS= read -r ts; do
  date -u -d "$ts" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null
done <<< "$ALL_TS")"

read -r ACTUAL_H ACTIVE_H IDLE_H <<EOF
$(echo "$EPOCHS" | sort -n | awk -v thresh="$IDLE_GAP_THRESHOLD_S" '
  NR==1 { first=$0; prev=$0; next }
  {
    gap = $0 - prev
    if (gap <= thresh) { active += gap } else { idle += gap }
    prev = $0
  }
  END {
    total = prev - first
    printf "%.3f %.3f %.3f", total/3600, active/3600, idle/3600
  }')
EOF

VARIANCE_PCT="$(awk -v e="$EXPECTED_H" -v a="$ACTIVE_H" 'BEGIN{ if (e+0==0) {print "null"} else {printf "%.1f", ((a-e)/e)*100} }')"

WITHIN_BOUND="null"
if [ -n "$PESSIMISTIC_H" ]; then
  WITHIN_BOUND="$(awk -v a="$ACTIVE_H" -v p="$PESSIMISTIC_H" 'BEGIN{print (a<=p) ? "true" : "false"}')"
fi

echo "{\"rd_id\":\"$RD_ID\",\"estimated_h\":$EXPECTED_H,\"optimistic_h\":${OPTIMISTIC_H:-null},\"pessimistic_h\":${PESSIMISTIC_H:-null},\"actual_h\":$ACTUAL_H,\"active_h\":$ACTIVE_H,\"idle_h\":$IDLE_H,\"idle_gap_threshold_s\":$IDLE_GAP_THRESHOLD_S,\"variance_pct\":$VARIANCE_PCT,\"within_pessimistic_bound\":$WITHIN_BOUND}"
