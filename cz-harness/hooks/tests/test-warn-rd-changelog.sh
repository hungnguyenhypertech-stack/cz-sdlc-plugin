#!/usr/bin/env bash
# Self-test for hooks/warn-rd-changelog.sh.
#
# Regression coverage: /cz:health-check (2026-08-10, AIBOOTCAMP) found 8/11
# version>=2 RDs with no notes: change-log at all — invisible to the
# pipeline until a manual audit walked every RD by hand. This script proves
# the hook flags a version>=2 RD with no notes:, stays silent once notes: is
# present, stays silent for a version-1 RD, and never emits the same
# (rd, version) advisory twice.
#
# Uses an isolated scratch CZ_ROOT — never touches the real plugin's state
# (see audit finding C5 about exactly that kind of contamination).
#
# Usage: bash hooks/tests/test-warn-rd-changelog.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../warn-rd-changelog.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd"

RD_FILE="$CZ_ROOT/rd/RD-TEST-001.01.md"

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
  local payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$RD_FILE\"}}"
  CZ_ROOT="$CZ_ROOT" bash -c "printf '%s' '$payload' | '$HOOK'" >/dev/null 2>&1
}

gap_count() {
  [ -f "$CZ_ROOT/telemetry/events.jsonl" ] || { echo 0; return; }
  grep -c '"event":"changelog_gap"' "$CZ_ROOT/telemetry/events.jsonl"
}

# Case A: version 1, no notes -> silent (nothing to change-log yet)
cat > "$RD_FILE" <<'EOF'
id: RD-TEST-001.01
version: 1
state: draft
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "version 1, no notes -> silent" "0" "$(gap_count)"

# Case B: version 2, no notes -> flagged
cat > "$RD_FILE" <<'EOF'
id: RD-TEST-001.01
version: 2
state: draft
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "version 2, no notes -> flagged" "1" "$(gap_count)"

# Case C: same file written again at the same version -> deduped, no new event
run_hook
check "re-touch at same version -> deduped" "1" "$(gap_count)"

# Case D: version 2, notes present -> silent
cat > "$RD_FILE" <<'EOF'
id: RD-TEST-001.01
version: 2
state: draft
notes: "explains the change"
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "version 2, notes present -> silent" "0" "$(gap_count)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
