#!/usr/bin/env bash
# Self-test for hooks/compute-estimate-variance.sh.
#
# Not wired into hooks.json (see its own header comment) — invoked directly
# by /cz:gate step 8, only on the "approved" branch, right before
# release-lock.sh. Computes wall-clock actual_h/active_h/idle_h from this
# RD's telemetry timestamps against its rd/*.md estimate.expected_h/
# .pessimistic, and prints one JSON object for embedding into
# gate-records/<rd-id>-gate.json's "estimate_variance" field. Deliberately
# time-only (no fabricated token/cost numbers — see the script's own header
# comment on this plugin's "honest zero, not a silent schema gap" rule).
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry.
#
# Usage: bash hooks/tests/test-compute-estimate-variance.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../compute-estimate-variance.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd" "$CZ_ROOT/telemetry"

TELEMETRY_FILE="$CZ_ROOT/telemetry/events.jsonl"

pass_count=0
fail_count=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc (expected $expected, got $actual)"
    pass_count=$((pass_count+1))
  else
    echo "FAIL: $desc (expected $expected, got $actual)" >&2
    fail_count=$((fail_count+1))
  fi
}

# json_num_field <json-line> <key>: pulls a bare numeric/null/bool field's
# value out of the hook's flat single-line JSON output.
json_num_field() {
  local json="$1" key="$2"
  echo "$json" | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*[A-Za-z0-9.+-]+" \
    | head -1 | sed -E "s/\"$key\"[[:space:]]*:[[:space:]]*//"
}

write_rd() {
  local id="$1" expected_h="$2" optimistic="$3" pessimistic="$4"
  cat > "$CZ_ROOT/rd/$id.md" <<EOF
id: $id
state: human_review
estimate:
  optimistic: $optimistic
  likely: 3
  pessimistic: $pessimistic
  expected_h: $expected_h
EOF
}

write_rd_no_estimate() {
  local id="$1"
  cat > "$CZ_ROOT/rd/$id.md" <<EOF
id: $id
state: human_review
EOF
}

emit_event() {
  local rd="$1" ts="$2" event="$3"
  echo "{\"ts\":\"$ts\",\"run_id\":\"r-1\",\"rd\":\"$rd\",\"agent\":\"dev\",\"event\":\"$event\",\"result\":\"ok\"}" >> "$TELEMETRY_FILE"
}

# epoch_to_iso <epoch-seconds>: portable-enough for this test's own use
# (matches cz_iso_to_epoch's BSD/GNU split in lib/common.sh).
epoch_to_iso() {
  date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ"
}

# emit_events_spaced <rd> <base-iso> <step-s> <count>: emits <count> events
# for <rd>, <step-s> seconds apart starting at <base-iso>. Used to build a
# span with NO gap exceeding IDLE_GAP_THRESHOLD_S (1800s), so the whole span
# lands in active_h rather than idle_h — a single event every hour (a first
# draft of this fixture used exactly that) would put every gap OVER the
# 1800s threshold and misclassify the entire span as idle.
emit_events_spaced() {
  local rd="$1" base_iso="$2" step="$3" count="$4" base_epoch i
  base_epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$base_iso" +%s 2>/dev/null \
    || date -u -d "$base_iso" +%s)"
  for ((i = 0; i < count; i++)); do
    emit_event "$rd" "$(epoch_to_iso $((base_epoch + i * step)))" "agent_heartbeat"
  done
}

run_compute() {
  local rd="$1"
  CZ_ROOT="$CZ_ROOT" bash "$HOOK" "$rd" 2>/tmp/cz-test-compute-estimate-variance.err
}

# --- Case: RD with no estimate on record -> honest null, not fabricated ---
RD_NOEST="RD-TEST-050.01"
write_rd_no_estimate "$RD_NOEST"
OUT="$(run_compute "$RD_NOEST")"
check "no estimate.expected_h -> estimated_h is null" "null" "$(json_num_field "$OUT" estimated_h)"
check "no estimate.expected_h -> actual_h is null (not fabricated)" "null" "$(json_num_field "$OUT" actual_h)"
check "no estimate.expected_h -> within_pessimistic_bound is null" "null" "$(json_num_field "$OUT" within_pessimistic_bound)"

# --- Case: RD has an estimate but zero telemetry at all -> honest null ----
RD_NOTEL="RD-TEST-050.02"
write_rd "$RD_NOTEL" 3.2 2 5
OUT="$(run_compute "$RD_NOTEL")"
check "estimate present, no telemetry for this rd -> actual_h is null" "null" "$(json_num_field "$OUT" actual_h)"
check "estimate present, no telemetry for this rd -> variance_pct is null" "null" "$(json_num_field "$OUT" variance_pct)"
check "estimate present, no telemetry for this rd -> estimated_h still echoed back" "3.2" "$(json_num_field "$OUT" estimated_h)"

# --- Case: normal arithmetic, clean telemetry, within pessimistic bound ---
# Span: 00:00:00 -> 02:00:00, heartbeats every 15min (900s, under the 1800s
# idle threshold) so the whole 2h span is "active", none of it "idle".
# estimated_h=3.2 -> variance = (2-3.2)/3.2*100 = -37.5%.
RD_CLEAN="RD-TEST-050.03"
write_rd "$RD_CLEAN" 3.2 2 5
emit_event "$RD_CLEAN" "2026-08-01T00:00:00Z" "rd_claim"
emit_events_spaced "$RD_CLEAN" "2026-08-01T00:00:00Z" 900 9   # 00:00 .. 02:00, every 15min
emit_event "$RD_CLEAN" "2026-08-01T02:00:00Z" "rd_state_change"
OUT="$(run_compute "$RD_CLEAN")"
check "clean case: estimated_h echoed" "3.2" "$(json_num_field "$OUT" estimated_h)"
check "clean case: actual_h = 2.000 (00:00 -> 02:00)" "2.000" "$(json_num_field "$OUT" actual_h)"
check "clean case: active_h = 2.000 (no gap over threshold)" "2.000" "$(json_num_field "$OUT" active_h)"
check "clean case: idle_h = 0.000" "0.000" "$(json_num_field "$OUT" idle_h)"
check "clean case: variance_pct = -37.5 ((2-3.2)/3.2*100)" "-37.5" "$(json_num_field "$OUT" variance_pct)"
check "clean case: within_pessimistic_bound = true (2h <= 5h pessimistic)" "true" "$(json_num_field "$OUT" within_pessimistic_bound)"

# --- Case: actual (active) time exceeds pessimistic -> bound is false -----
# Span: 00:00:00 -> 10:00:00 (10h), heartbeats every 30min (1800s, AT the
# idle threshold — "<= thresh" still counts as active), pessimistic=5h.
RD_OVER="RD-TEST-050.04"
write_rd "$RD_OVER" 3.2 2 5
emit_event "$RD_OVER" "2026-08-01T00:00:00Z" "rd_claim"
emit_events_spaced "$RD_OVER" "2026-08-01T00:00:00Z" 1800 21   # 00:00 .. 10:00, every 30min
emit_event "$RD_OVER" "2026-08-01T10:00:00Z" "rd_state_change"
OUT="$(run_compute "$RD_OVER")"
check "over-budget case: active_h = 10.000" "10.000" "$(json_num_field "$OUT" active_h)"
check "over-budget case: within_pessimistic_bound = false (10h > 5h pessimistic)" "false" "$(json_num_field "$OUT" within_pessimistic_bound)"

# --- Case: a long idle gap (queued behind max_in_flight, human wait, etc.)
# is excluded from active_h but still counted in actual_h/idle_h. Gap from
# 00:00 -> 05:00 is 5h (18000s), well over the 1800s IDLE_GAP_THRESHOLD_S.
RD_IDLE="RD-TEST-050.05"
write_rd "$RD_IDLE" 3.2 2 5
emit_event "$RD_IDLE" "2026-08-01T00:00:00Z" "rd_claim"
emit_event "$RD_IDLE" "2026-08-01T00:10:00Z" "agent_heartbeat"
emit_event "$RD_IDLE" "2026-08-01T05:00:00Z" "rd_state_change"
OUT="$(run_compute "$RD_IDLE")"
check "idle-gap case: actual_h = 5.000 (raw wall-clock span)" "5.000" "$(json_num_field "$OUT" actual_h)"
check "idle-gap case: active_h excludes the >1800s gap (only the 10min leg counts)" "0.167" "$(json_num_field "$OUT" active_h)"
check "idle-gap case: within_pessimistic_bound computed against active_h, not actual_h (0.167h <= 5h -> true)" "true" \
  "$(json_num_field "$OUT" within_pessimistic_bound)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
