#!/usr/bin/env bash
# Self-test for hooks/restamp-lock.sh.
#
# Not wired into hooks.json (see its own header comment and hooks.json's
# notes) — invoked directly by /cz:build's inner loop to re-label an
# ALREADY-HELD RD lock's agent= field when work hands off between roles
# (test-designer -> dev -> back to the outer cz-build loop), deliberately
# skipping guard-claim-lock.sh's contention/TTL arbitration since this is a
# relabel within the same claim, not a competing claim attempt.
# Contract: $1 = RD id, $2 = new agent name.
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry.
#
# Usage: bash hooks/tests/test-restamp-lock.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../restamp-lock.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/state/locks" "$CZ_ROOT/telemetry"

LOCK_DIR="$CZ_ROOT/state/locks"
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

run_restamp() {
  local rd="$1" agent="$2"
  if CZ_ROOT="$CZ_ROOT" bash "$HOOK" "$rd" "$agent" \
      >/tmp/cz-test-restamp-lock.out 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# --- Error paths: missing args ---------------------------------------------
check "missing RD id -> deny" "deny" "$(run_restamp "" "dev")"
check "missing new agent -> deny" "deny" "$(run_restamp "RD-TEST-040.01" "")"

# --- Error path: no active lock to restamp ---------------------------------
RD_ID="RD-TEST-040.01"
check "restamp on RD with no active lock -> deny" "deny" "$(run_restamp "$RD_ID" "dev")"
check "no lock file created by the failed restamp" "0" \
  "$([ -f "$LOCK_DIR/$RD_ID.lock" ] && echo 1 || echo 0)"

# --- Normal restamp: refreshes agent= and ts= on an already-held lock -----
OLD_TS="2020-01-01T00:00:00Z"
cat > "$LOCK_DIR/$RD_ID.lock" <<EOF
agent=test-designer
ts=$OLD_TS
EOF

# A different RD's lock must be left untouched by this call.
OTHER_RD="RD-TEST-041.01"
cat > "$LOCK_DIR/$OTHER_RD.lock" <<EOF
agent=dev
ts=$OLD_TS
EOF

check "normal restamp -> allow" "allow" "$(run_restamp "$RD_ID" "dev")"

check "lock file now shows the new agent" "1" \
  "$(grep -qE '^agent=dev$' "$LOCK_DIR/$RD_ID.lock" 2>/dev/null && echo 1 || echo 0)"
check "lock file's ts= was refreshed (no longer the old backdated value)" "1" \
  "$(grep -qE "^ts=$OLD_TS\$" "$LOCK_DIR/$RD_ID.lock" 2>/dev/null && echo 0 || echo 1)"
check "lock_restamped telemetry event emitted for this RD" "1" \
  "$(grep -qF "\"rd\":\"$RD_ID\"" "$TELEMETRY_FILE" 2>/dev/null \
      && grep -qF '"event":"lock_restamped"' "$TELEMETRY_FILE" 2>/dev/null \
      && echo 1 || echo 0)"
check "lock_restamped event records the new agent" "1" \
  "$(grep -qF "\"rd\":\"$RD_ID\",\"agent\":\"dev\",\"event\":\"lock_restamped\"" "$TELEMETRY_FILE" 2>/dev/null && echo 1 || echo 0)"
check "lock_restamped event's result names the OLD agent it restamped from" "1" \
  "$(grep -qF '"result":"restamped_from_test-designer"' "$TELEMETRY_FILE" 2>/dev/null && echo 1 || echo 0)"

check "a different RD's lock is left untouched by this restamp" "1" \
  "$(grep -qE '^agent=dev$' "$LOCK_DIR/$OTHER_RD.lock" 2>/dev/null \
      && grep -qE "^ts=$OLD_TS\$" "$LOCK_DIR/$OTHER_RD.lock" 2>/dev/null \
      && echo 1 || echo 0)"

# --- Re-entrant restamp works again (e.g. dev -> back to test-designer) ---
check "second restamp on the same RD (dev -> test-designer) -> allow" "allow" \
  "$(run_restamp "$RD_ID" "test-designer")"
check "lock file now shows test-designer again" "1" \
  "$(grep -qE '^agent=test-designer$' "$LOCK_DIR/$RD_ID.lock" 2>/dev/null && echo 1 || echo 0)"
check "second lock_restamped event's result names dev as the agent restamped from" "1" \
  "$(grep -qF '"result":"restamped_from_dev"' "$TELEMETRY_FILE" 2>/dev/null && echo 1 || echo 0)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
