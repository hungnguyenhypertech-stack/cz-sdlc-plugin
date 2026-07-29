#!/usr/bin/env bash
# Self-test for hooks/guard-red-before-green.sh (audit finding M1).
#
# Regression coverage: evidence.red_log is stored (and documented in
# rd-template.yaml) as a path RELATIVE TO CZ_ROOT, but the hook used to test
# `[ -f "$RED_LOG" ]` against that relative path as-is — which resolves
# against the INVOKING PROCESS's cwd, not CZ_ROOT. The "should-pass" case (a
# genuinely valid, hash-matching red log) was the one that broke: it only
# passed when cwd happened to equal CZ_ROOT. The fix anchors RED_LOG to
# CZ_ROOT explicitly whenever it isn't already absolute. This script proves
# the valid case now passes when invoked from a cwd that is deliberately NOT
# CZ_ROOT — exactly the scenario that used to fail.
#
# Usage: bash hooks/tests/test-guard-red-before-green.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-red-before-green.sh"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/rd" "$SCRATCH/state/locks" "$SCRATCH/evidence/RD-TEST-002.01" "$SCRATCH/src/reconciliation"

# A cwd that is deliberately NOT CZ_ROOT — this is the case M1 broke.
OTHER_CWD="$(mktemp -d)"
trap 'rm -rf "$OTHER_CWD"' EXIT

cat > "$SCRATCH/state/locks/RD-TEST-002.01.lock" <<'EOF'
agent=dev
ts=2026-07-29T00:00:00Z
ttl=999999
EOF

write_rd() {
  local state="$1"
  cat > "$SCRATCH/rd/RD-TEST-002.01.md" <<EOF
id: RD-TEST-002.01
version: 1
content_hash: "sha256:ABCDEF"
state: $state
evidence:
  red_log: evidence/RD-TEST-002.01/tests-red-v1.log
  green_log: null
EOF
}

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

# run_from <cwd>: invokes the hook with cwd set to <cwd> but CZ_ROOT fixed at
# $SCRATCH, and prints allow/deny.
run_from() {
  local cwd="$1"
  if (cd "$cwd" && CZ_ROOT="$SCRATCH" bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"./src/reconciliation/refresh_guard.py\"}}' | '$HOOK'") >/dev/null 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# Case 1: no red log at all -> DENY, from either cwd
write_rd "claimed"
check "no red log (from CZ_ROOT)" "deny" "$(run_from "$SCRATCH")"
check "no red log (from other cwd)" "deny" "$(run_from "$OTHER_CWD")"

# Case 2: red log exists but hash doesn't match -> DENY
cat > "$SCRATCH/evidence/RD-TEST-002.01/tests-red-v1.log" <<'EOF'
# derived against "sha256:STALEHASH"
2 failed, 0 passed
EOF
write_rd "red"
check "stale-hash red log (from other cwd)" "deny" "$(run_from "$OTHER_CWD")"

# Case 3: valid red log, matching hash, real recorded failure -> ALLOW,
# INCLUDING when invoked from a cwd that is not CZ_ROOT (the M1 regression).
cat > "$SCRATCH/evidence/RD-TEST-002.01/tests-red-v1.log" <<'EOF'
# derived against "sha256:ABCDEF"
2 failed, 0 passed
EOF
check "valid red log (from CZ_ROOT)" "allow" "$(run_from "$SCRATCH")"
check "valid red log (from OTHER cwd — the M1 regression case)" "allow" "$(run_from "$OTHER_CWD")"

# Case 4: red log present but records no real failure (e.g. a collection
# error) -> DENY
cat > "$SCRATCH/evidence/RD-TEST-002.01/tests-red-v1.log" <<'EOF'
# derived against "sha256:ABCDEF"
ERROR collecting tests
EOF
check "red log with no real failure (from other cwd)" "deny" "$(run_from "$OTHER_CWD")"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
