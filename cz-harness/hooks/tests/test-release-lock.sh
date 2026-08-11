#!/usr/bin/env bash
# Self-test for hooks/release-lock.sh's heartbeat cleanup.
#
# Live incident: RD-AIBOOTCAMP-005.01c finished normally (DoR passed, gate-1
# approved, board state "accepted") but state/heartbeats/{dev,test-designer,
# cz-build,ai-reviewer}.hb stayed frozen at agent_state "executing" because
# nothing ever cleared them once the lock was released — /cz:status and
# board.html derive "stalled" purely from agent_state=="executing" + heartbeat
# age, so those four files read as a permanent false stall. Fixed here:
# release-lock.sh now deletes every state/heartbeats/*.hb file whose "rd"
# field matches the RD being released. (project-state.sh separately guards
# against any heartbeat this step misses — see test-project-state.sh.)
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry (audit finding C5's contamination story).
#
# Usage: bash hooks/tests/test-release-lock.sh

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
HOOK="$DIR/../release-lock.sh"

export CZ_ROOT
CZ_ROOT="$(cz_test_tmpdir)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/state/locks" "$CZ_ROOT/state/heartbeats" "$CZ_ROOT/telemetry" \
         "$CZ_ROOT/rd" "$CZ_ROOT/gate-records" "$CZ_ROOT/config"

pass_count=0
fail_count=0

check() {
  local desc="$1" cond="$2"
  if [ "$cond" = "1" ]; then
    echo "PASS: $desc"
    pass_count=$((pass_count+1))
  else
    echo "FAIL: $desc" >&2
    fail_count=$((fail_count+1))
  fi
}

RD_ID="RD-TEST-005.01c"
OTHER_RD_ID="RD-TEST-999.99"

cat > "$CZ_ROOT/state/locks/$RD_ID.lock" <<EOF
agent=dev
ts=2026-07-30T07:55:00Z
EOF

# Four agents that all touched this RD across its lifecycle — matches the
# real dev/test-designer/cz-build/ai-reviewer set from the live incident.
for agent in dev test-designer cz-build ai-reviewer; do
  cat > "$CZ_ROOT/state/heartbeats/$agent.hb" <<EOF
{"last_heartbeat":"2026-07-30T08:02:00Z","agent_state":"executing","rd":"$RD_ID"}
EOF
done

# A heartbeat for a DIFFERENT, still-active RD — must survive the release.
cat > "$CZ_ROOT/state/heartbeats/other-agent.hb" <<EOF
{"last_heartbeat":"2026-07-30T08:02:00Z","agent_state":"executing","rd":"$OTHER_RD_ID"}
EOF

CZ_ROOT="$CZ_ROOT" bash "$HOOK" "$RD_ID" accepted >/tmp/cz-test-release-lock.out 2>&1
HOOK_EXIT=$?
check "release-lock.sh exits 0" "$([ "$HOOK_EXIT" -eq 0 ] && echo 1 || echo 0)"

check "lock file removed" "$([ ! -f "$CZ_ROOT/state/locks/$RD_ID.lock" ] && echo 1 || echo 0)"

ALL_CLEARED=1
for agent in dev test-designer cz-build ai-reviewer; do
  [ -f "$CZ_ROOT/state/heartbeats/$agent.hb" ] && ALL_CLEARED=0
done
check "all four heartbeat files pinned to the released RD are deleted" "$ALL_CLEARED"

check "heartbeat for a different, still-active RD is left untouched" \
  "$([ -f "$CZ_ROOT/state/heartbeats/other-agent.hb" ] && echo 1 || echo 0)"

check "rd_release event emitted to telemetry" \
  "$(grep -qF "\"event\":\"rd_release\"" "$CZ_ROOT/telemetry/events.jsonl" 2>/dev/null && echo 1 || echo 0)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
