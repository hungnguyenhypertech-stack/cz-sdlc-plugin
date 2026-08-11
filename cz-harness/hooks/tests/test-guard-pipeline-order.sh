#!/usr/bin/env bash
# Self-test for hooks/guard-pipeline-order.sh (audit finding M4).
#
# Regression coverage: every commands/cz-*.md pipeline-step file documents a
# "Gate check: refuse unless gate-records/PB<n>-*.json status:passed" rule in
# prose, but nothing in hooks.json ever enforced it mechanically — unlike the
# RD-level sub-flow (hooks/guard-state-transition.sh), the outer pipeline's
# "step n+1 is refused until step n has a passed gate record" rule (plan
# §8.2) was advisory only. This script proves the new hook actually denies a
# next-step deliverable write when the preceding phase gate is missing/failed,
# allows it once that gate record shows status:passed, and never blocks step
# 0 (which has no predecessor per plan §8.2).
#
# Uses an isolated scratch CZ_ROOT — never touches the real plugin's state
# (see audit finding C5 about exactly that kind of contamination).
#
# Usage: bash hooks/tests/test-guard-pipeline-order.sh

set -uo pipefail

# --- portability helpers (see hooks/lib/common.sh for the product-side twins) --
# cz_test_tmpdir: a scratch dir both the shell AND a native python can open.
# Under Git Bash/MSYS, mktemp -d returns a virtual path (/tmp/...) that a
# native Windows python cannot open, so every python-based assertion below
# silently read an empty file and failed. cygpath -m yields a form both
# accept; no-op on Linux/macOS, where cygpath does not exist.
cz_test_tmpdir() {
  local d
  d="$(command mktemp -d)"
  if command -v cygpath >/dev/null 2>&1; then
    d="$(cygpath -m "$d")"
  fi
  echo "$d"
}

# cz_test_python: an interpreter that actually RUNS. `python3` on Windows is
# an App Execution Alias stub that exists and always fails. Mirrors cz_python
# in hooks/lib/common.sh.
cz_test_python() {
  local c
  for c in "${CZ_PYTHON_BIN:-}" python3 python py; do
    [ -n "$c" ] || continue
    command -v "$c" >/dev/null 2>&1 || continue
    if "$c" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  echo "python3"
  return 0
}
PYBIN="$(cz_test_python)"
# ------------------------------------------------------------------------------
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-pipeline-order.sh"

export CZ_ROOT
CZ_ROOT="$(cz_test_tmpdir)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/deliverables" "$CZ_ROOT/gate-records"

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

# run_write <file_path>: feeds a minimal Write tool-call payload targeting
# <file_path> to the hook; prints "allow" or "deny".
run_write() {
  local file_path="$1"
  local payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$file_path\"}}"
  if CZ_ROOT="$CZ_ROOT" bash -c "printf '%s' '$payload' | '$HOOK'" >/dev/null 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

write_gate_record() {
  local name="$1" status="$2"
  cat > "$CZ_ROOT/gate-records/$name" <<EOF
{"step": 0, "project": "TEST", "status": "$status", "approver": "auto", "timestamp": "2026-07-29T00:00:00Z"}
EOF
}

rm_gate_record() { rm -f "$CZ_ROOT/gate-records/$1"; }

# --- Case 1: writing deliverables/SPEC-TEST.md with NO prior PB0-*.json at
# all -> DENY.
rm -f "$CZ_ROOT/gate-records/PB0-scope.json"
check "SPEC with no PB0 gate record at all" "deny" "$(run_write "$CZ_ROOT/deliverables/SPEC-TEST.md")"

# --- Case 2: PB0-scope.json present but status:failed -> DENY.
write_gate_record "PB0-scope.json" "failed"
check "SPEC with PB0 gate record present but status:failed" "deny" "$(run_write "$CZ_ROOT/deliverables/SPEC-TEST.md")"

# --- Case 2b: PB0-scope.json present but status:pending (neither passed nor
# failed) -> DENY, same rule.
write_gate_record "PB0-scope.json" "pending"
check "SPEC with PB0 gate record present but status:pending" "deny" "$(run_write "$CZ_ROOT/deliverables/SPEC-TEST.md")"

# --- Case 3: PB0-scope.json present and status:passed -> ALLOW.
write_gate_record "PB0-scope.json" "passed"
check "SPEC with PB0 gate record status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/SPEC-TEST.md")"

# --- Case 4: writing deliverables/SCOPE-TEST.md (step 0, no predecessor)
# with NO gate records anywhere -> ALLOW (step 0 is never blocked).
rm -f "$CZ_ROOT/gate-records/PB0-scope.json"
check "SCOPE (step 0) with zero gate records anywhere" "allow" "$(run_write "$CZ_ROOT/deliverables/SCOPE-TEST.md")"

# --- Extra coverage: chain a couple more phase steps to prove the predecessor
# lookup targets the RIGHT prior gate, not just "any gate record exists".
write_gate_record "PB0-scope.json" "passed"
rm_gate_record "PB1-spec.json"
check "MODULEMAP denied when PB1-spec.json missing (even though PB0 passed)" "deny" "$(run_write "$CZ_ROOT/deliverables/MODULEMAP-TEST.md")"
write_gate_record "PB1-spec.json" "passed"
check "MODULEMAP allowed once PB1-spec.json is status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/MODULEMAP-TEST.md")"

# --- Extra coverage: RISK and DELEGATION-MAP (both step 6 outputs) share the
# same PB5-estimate.json predecessor.
rm_gate_record "PB5-estimate.json"
check "RISK denied with no PB5-estimate.json" "deny" "$(run_write "$CZ_ROOT/deliverables/RISK-TEST.md")"
check "DELEGATION-MAP denied with no PB5-estimate.json" "deny" "$(run_write "$CZ_ROOT/deliverables/DELEGATION-MAP-TEST.md")"
write_gate_record "PB5-estimate.json" "passed"
check "RISK allowed once PB5-estimate.json is status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/RISK-TEST.md")"
check "DELEGATION-MAP allowed once PB5-estimate.json is status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/DELEGATION-MAP-TEST.md")"

# --- Extra coverage: DOR (step 7, per-RD deliverable) still checks the
# PHASE-level PB6-risk.json, never a per-RD record — must not be conflated
# with the per-RD DEVBOOK check below (plan §4.3).
rm_gate_record "PB6-risk.json"
check "DOR denied with no PB6-risk.json (phase gate, not per-RD)" "deny" "$(run_write "$CZ_ROOT/deliverables/DOR-RD-TEST-001.01.md")"
write_gate_record "PB6-risk.json" "passed"
check "DOR allowed once PB6-risk.json is status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/DOR-RD-TEST-001.01.md")"

# --- Extra coverage: DEVBOOK (step 8, per-RD) checks the SAME RD's own
# gate-records/<rd-id>-dor.json, not the phase gate — proves the RD-level
# vs. phase-level distinction is not conflated in the other direction either.
rm -f "$CZ_ROOT/gate-records/RD-TEST-001.01-dor.json"
check "DEVBOOK denied with no per-RD dor gate record" "deny" "$(run_write "$CZ_ROOT/deliverables/DEVBOOK-RD-TEST-001.01.md")"
cat > "$CZ_ROOT/gate-records/RD-TEST-001.01-dor.json" <<'EOF'
{"rd_id": "RD-TEST-001.01", "status": "failed", "approver": "auto", "timestamp": "2026-07-29T00:00:00Z"}
EOF
check "DEVBOOK denied when per-RD dor gate record status:failed" "deny" "$(run_write "$CZ_ROOT/deliverables/DEVBOOK-RD-TEST-001.01.md")"
cat > "$CZ_ROOT/gate-records/RD-TEST-001.01-dor.json" <<'EOF'
{"rd_id": "RD-TEST-001.01", "status": "passed", "approver": "auto", "timestamp": "2026-07-29T00:00:00Z"}
EOF
check "DEVBOOK allowed once THIS RD's own dor gate record is status:passed" "allow" "$(run_write "$CZ_ROOT/deliverables/DEVBOOK-RD-TEST-001.01.md")"
# A different RD's DEVBOOK must NOT ride on RD-TEST-001.01's passed DoR.
check "a DIFFERENT RD's DEVBOOK still denied (no dor record for it)" "deny" "$(run_write "$CZ_ROOT/deliverables/DEVBOOK-RD-TEST-002.01.md")"

# --- Extra coverage: RTM/WEEKLY/CASE-STUDY (step 10) require at least one
# RD-level gate.json anywhere with gate_decision.decision:"approved" —
# project-wide, not tied to one RD id.
rm -f "$CZ_ROOT"/gate-records/*-gate.json
check "RTM denied with zero *-gate.json records" "deny" "$(run_write "$CZ_ROOT/deliverables/RTM-TEST.md")"
cat > "$CZ_ROOT/gate-records/RD-TEST-001.01-gate.json" <<'EOF'
{"rd_id": "RD-TEST-001.01", "gate_decision": {"approver": "auto", "decision": "approved", "timestamp": "2026-07-29T00:00:00Z"}}
EOF
check "RTM allowed once any RD has decision:approved" "allow" "$(run_write "$CZ_ROOT/deliverables/RTM-TEST.md")"
check "WEEKLY allowed off the same any-RD-approved signal" "allow" "$(run_write "$CZ_ROOT/deliverables/WEEKLY-TEST.md")"
check "CASE-STUDY.md allowed off the same any-RD-approved signal" "allow" "$(run_write "$CZ_ROOT/deliverables/CASE-STUDY.md")"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
