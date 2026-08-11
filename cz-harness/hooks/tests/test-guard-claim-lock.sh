#!/usr/bin/env bash
# Self-test for hooks/guard-claim-lock.sh.
#
# guard-claim-lock.sh is NOT wired into hooks.json (see its own header
# comment and hooks.json's notes) — it is invoked directly by /cz:rd and
# /cz:build at claim time, contract: $1 = RD id (or env CZ_ACTIVE_RD), env
# CZ_ACTING_AGENT = claiming agent. Covers plan §6.3 invariants 2-3:
#   - one RD, one lock (same-agent re-entrant OK, different-agent denied)
#   - TTL-expired locks are lazily reclaimed (lock_reclaimed telemetry)
#   - hazard RDs (rd/<id>.md's `hazard: true`) refuse to claim while ANY
#     other RD holds a lock, even a non-hazard one ("hazard work runs alone")
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry (audit finding C5's contamination story).
#
# Usage: bash hooks/tests/test-guard-claim-lock.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-claim-lock.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/state/locks" "$CZ_ROOT/rd" "$CZ_ROOT/telemetry" "$CZ_ROOT/config"

TELEMETRY_FILE="$CZ_ROOT/telemetry/events.jsonl"
LOCK_DIR="$CZ_ROOT/state/locks"

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

# run_claim <rd-id> <agent>: invokes the hook, prints allow/deny.
# An empty <rd-id>/<agent> arg is passed through as "" — guard-claim-lock.sh
# treats an unset-or-empty $1/$CZ_ACTING_AGENT identically (bash `${x:-}`).
run_claim() {
  local rd="$1" agent="$2"
  if CZ_ROOT="$CZ_ROOT" CZ_ACTING_AGENT="$agent" bash "$HOOK" "$rd" \
      >/tmp/cz-test-guard-claim-lock.out 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# --- Case (a): missing RD id or missing acting agent -> deny -------------
check "missing RD id -> deny" "deny" "$(run_claim "" "dev")"
check "missing acting agent -> deny" "deny" "$(run_claim "RD-TEST-030.01" "")"

# --- Case (b): fresh claim on an unlocked RD -> allow ---------------------
RD_A="RD-TEST-030.01"
check "fresh claim on unlocked RD -> allow" "allow" "$(run_claim "$RD_A" "dev")"

LOCK_FILE="$LOCK_DIR/$RD_A.lock"
check "lock file created" "1" "$([ -f "$LOCK_FILE" ] && echo 1 || echo 0)"
check "lock file has agent= line for dev" "1" \
  "$(grep -qE '^agent=dev$' "$LOCK_FILE" 2>/dev/null && echo 1 || echo 0)"
check "lock file has ts= line" "1" \
  "$(grep -qE '^ts=' "$LOCK_FILE" 2>/dev/null && echo 1 || echo 0)"
check "rd_claim telemetry event emitted" "1" \
  "$(grep -qF "\"rd\":\"$RD_A\"" "$TELEMETRY_FILE" 2>/dev/null \
      && grep -qF '"event":"rd_claim"' "$TELEMETRY_FILE" 2>/dev/null \
      && echo 1 || echo 0)"

RD_CLAIM_COUNT_AFTER_B="$(grep -c '"event":"rd_claim"' "$TELEMETRY_FILE" 2>/dev/null || echo 0)"

# --- Case (c): re-claim by the SAME agent while lock is fresh -> allow ----
# (re-entrant; must NOT emit a second rd_claim for the same physical claim)
check "re-claim by same agent (fresh lock) -> allow" "allow" "$(run_claim "$RD_A" "dev")"
RD_CLAIM_COUNT_AFTER_C="$(grep -c '"event":"rd_claim"' "$TELEMETRY_FILE" 2>/dev/null || echo 0)"
check "re-entrant claim does not emit a second rd_claim event" "$RD_CLAIM_COUNT_AFTER_B" "$RD_CLAIM_COUNT_AFTER_C"

# --- Case (d): claim attempt by a DIFFERENT agent while lock is fresh -> deny
check "different agent while lock fresh -> deny" "deny" "$(run_claim "$RD_A" "test-designer")"
check "lock still held by original agent after denied claim" "1" \
  "$(grep -qE '^agent=dev$' "$LOCK_FILE" 2>/dev/null && echo 1 || echo 0)"

# --- Case (e): claim when existing lock is STALE (age >= TTL 1800s) -------
# Backdate the lock file's ts= line to simulate an expired hold.
cat > "$LOCK_FILE" <<EOF
agent=dev
ts=2000-01-01T00:00:00Z
EOF
check "claim on stale lock (different agent) -> allow, reclaims" "allow" "$(run_claim "$RD_A" "test-designer")"
check "reclaimed lock now shows the new agent" "1" \
  "$(grep -qE '^agent=test-designer$' "$LOCK_FILE" 2>/dev/null && echo 1 || echo 0)"
check "lock_reclaimed telemetry event emitted" "1" \
  "$(grep -qF "\"rd\":\"$RD_A\"" "$TELEMETRY_FILE" 2>/dev/null \
      && grep -qF '"event":"lock_reclaimed"' "$TELEMETRY_FILE" 2>/dev/null \
      && echo 1 || echo 0)"
check "reclaim does NOT double-emit rd_claim (only lock_reclaimed for this transition)" "$RD_CLAIM_COUNT_AFTER_C" \
  "$(grep -c '"event":"rd_claim"' "$TELEMETRY_FILE" 2>/dev/null || echo 0)"

# --- Case (f): hazard RD claim while ANY other lock exists -> deny --------
# $RD_A's lock (a non-hazard, unrelated RD from test-designer's reclaim
# above) is still held — this alone must block a hazard RD's claim.
RD_HAZARD="RD-TEST-031.01"
cat > "$CZ_ROOT/rd/$RD_HAZARD.md" <<EOF
id: $RD_HAZARD
state: ready
hazard: true
EOF
check "hazard RD claim while another (non-hazard) RD holds a lock -> deny" "deny" \
  "$(run_claim "$RD_HAZARD" "dev")"
check "hazard RD gets no lock file on denied claim" "0" \
  "$([ -f "$LOCK_DIR/$RD_HAZARD.lock" ] && echo 1 || echo 0)"

# --- Case (g): hazard RD claim when NO other locks exist -> allow ---------
rm -f "$LOCK_DIR"/*.lock
check "hazard RD claim with zero other locks -> allow" "allow" "$(run_claim "$RD_HAZARD" "dev")"
check "hazard RD's own lock file created" "1" \
  "$([ -f "$LOCK_DIR/$RD_HAZARD.lock" ] && echo 1 || echo 0)"
check "rd_claim telemetry event emitted for hazard RD" "1" \
  "$(grep -qF "\"rd\":\"$RD_HAZARD\"" "$TELEMETRY_FILE" 2>/dev/null \
      && grep -qF '"event":"rd_claim"' "$TELEMETRY_FILE" 2>/dev/null \
      && echo 1 || echo 0)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
