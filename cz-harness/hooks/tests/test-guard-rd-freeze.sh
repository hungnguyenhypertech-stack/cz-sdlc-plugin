#!/usr/bin/env bash
# Self-test for hooks/guard-rd-freeze.sh (audit finding C4).
#
# Regression coverage: the TC-level half of the freeze rule (plan §5.3) used
# to look for tests/.meta/*.rdhash sidecar files that nothing else in the
# plugin ever wrote, so it was dead code — only an RD's own `state: stale`
# ever blocked writes. The fix reads each linked TC's own `rd_hash:` field
# (tests/.meta/<tc-id>.yaml, per tc-template.yaml) and compares it to the
# RD's current content_hash directly, using the RD's own `tests:` list to
# know which TC files to check.
#
# Uses an isolated scratch CZ_ROOT — never touches the real plugin's state.
#
# Usage: bash hooks/tests/test-guard-rd-freeze.sh

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
HOOK="$DIR/../guard-rd-freeze.sh"

SCRATCH="$(cz_test_tmpdir)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/rd" "$SCRATCH/tests/.meta" "$SCRATCH/state/locks"

RD_FILE="$SCRATCH/rd/RD-TEST-001.01.md"
write_rd() {
  local state="$1"
  cat > "$RD_FILE" <<EOF
id: RD-TEST-001.01
version: 2
content_hash: "sha256:CURRENTHASH"
state: $state
tests:
  - TC-TEST-001.01-1
  - TC-TEST-001.01-2
EOF
}

cat > "$SCRATCH/state/locks/RD-TEST-001.01.lock" <<'EOF'
agent=dev
ts=2026-07-29T00:00:00Z
ttl=999999
EOF

write_tc() {
  local id="$1" hash="$2"
  cat > "$SCRATCH/tests/.meta/$id.yaml" <<EOF
id: $id
rd_hash: "$hash"
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

run_write() {
  local out
  if CZ_ROOT="$SCRATCH" bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"./src/reconciliation/refresh_guard.py\"}}' | '$HOOK'" >/dev/null 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# Case A: both TCs fresh (matching hash) -> ALLOW
write_rd "red"
write_tc "TC-TEST-001.01-1" "sha256:CURRENTHASH"
write_tc "TC-TEST-001.01-2" "sha256:CURRENTHASH"
check "both TCs fresh" "allow" "$(run_write)"

# Case B: one linked TC stale (hash mismatch) -> DENY
write_tc "TC-TEST-001.01-2" "sha256:OLDHASH"
check "one linked TC stale" "deny" "$(run_write)"

# Case C: RD's own state is stale -> DENY (unaffected by the C4 change,
# proves the pre-existing RD-level check still works alongside the new one)
write_tc "TC-TEST-001.01-2" "sha256:CURRENTHASH"
write_rd "stale"
check "RD state itself stale" "deny" "$(run_write)"

# Case D: linked TC file doesn't exist yet (not yet derived) -> ALLOW
# (a missing TC is an RTM orphan concern, §5.4 — not this guard's job)
write_rd "red"
rm -f "$SCRATCH/tests/.meta/TC-TEST-001.01-2.yaml"
check "linked TC not yet derived" "allow" "$(run_write)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
