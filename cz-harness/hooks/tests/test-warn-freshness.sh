#!/usr/bin/env bash
# Self-test for hooks/warn-freshness.sh.
#
# Regression coverage: /cz:health-check (2026-08-10, AIBOOTCAMP) found 9
# files under src/**/tests/** still citing a withdrawn/superseded RD id
# (Freshness), and 2 REQs whose entire RD lineage had gone dead with no live
# successor (Coverage's "lineage-exhausted" case) — both invisible to a pure
# graph check, both found only by a manual audit walking every RD by hand.
# This script proves both checks fire at the moment a transition makes them
# true, dedupe per (rd, citing file) / per REQ, and stay silent when a live
# sibling RD still covers the same REQ.
#
# Uses an isolated scratch CZ_ROOT — never touches the real plugin's state
# (see audit finding C5 about exactly that kind of contamination).
#
# Usage: bash hooks/tests/test-warn-freshness.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../warn-freshness.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd" "$CZ_ROOT/src" "$CZ_ROOT/tests"

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

run_hook() {
  local rd_file="$1"
  local payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$rd_file\"}}"
  CZ_ROOT="$CZ_ROOT" bash -c "printf '%s' '$payload' | '$HOOK'" >/dev/null 2>&1
}

event_count() {
  local event="$1"
  [ -f "$CZ_ROOT/telemetry/events.jsonl" ] || { echo 0; return; }
  grep -c "\"event\":\"$event\"" "$CZ_ROOT/telemetry/events.jsonl"
}

# --- Freshness: citation of a just-withdrawn RD -----------------------
RD1="$CZ_ROOT/rd/RD-TEST-009.01.md"
cat > "$RD1" <<'EOF'
id: RD-TEST-009.01
state: withdrawn
parent_req: REQ-TEST-999
EOF
echo "// RD-TEST-009.01 content_hash: sha256:xyz" > "$CZ_ROOT/tests/citing.test.js"
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook "$RD1"
check "citation of withdrawn RD -> flagged" "1" "$(event_count citation_stale)"

run_hook "$RD1"
check "re-touch, same citation -> deduped" "1" "$(event_count citation_stale)"

# --- Coverage: lineage-exhausted (only RD for its REQ just died) ------
check "lineage exhausted (sole RD died) -> flagged" "1" "$(event_count lineage_exhausted)"

# --- Negative control: a live sibling RD covers the same REQ ----------
RD2="$CZ_ROOT/rd/RD-TEST-002.01.md"
RD2B="$CZ_ROOT/rd/RD-TEST-002.01b.md"
cat > "$RD2B" <<'EOF'
id: RD-TEST-002.01b
state: accepted
parent_req: REQ-TEST-023
EOF
cat > "$RD2" <<'EOF'
id: RD-TEST-002.01
state: superseded
parent_req: REQ-TEST-023
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook "$RD2"
check "live sibling covers REQ -> lineage NOT flagged" "0" "$(event_count lineage_exhausted)"

# --- Negative control: RD still red (not dead) -> silent on both checks
RD3="$CZ_ROOT/rd/RD-TEST-003.01.md"
cat > "$RD3" <<'EOF'
id: RD-TEST-003.01
state: red
parent_req: REQ-TEST-500
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook "$RD3"
check "RD still red (not dead) -> no citation events" "0" "$(event_count citation_stale)"
check "RD still red (not dead) -> no lineage events" "0" "$(event_count lineage_exhausted)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
