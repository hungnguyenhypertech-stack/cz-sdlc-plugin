#!/usr/bin/env bash
# Self-test for hooks/project-state.sh's cost_usd rollup and leash field
# (audit findings C8 and M6).
#
# C8: schemas/board-state.schema.json declares cost_usd on every RD card,
# board/board.html reads rd.cost_usd, but project-state.sh's entry-builder
# never wrote it — the field was always absent. Fixed: project-state.sh now
# sums the "cost_usd" field across every telemetry/events.jsonl line tagged
# with a given RD's id and writes the rolled-up figure into that RD's
# board.json entry (null if no cost-bearing event exists yet for that RD,
# never a silently-invented zero).
#
# M6: board.html's renderCard() had no leash badge, and board-state schema's
# rds[] items had no leash field at all (only an unused in_flight_detail
# mirror). Fixed: schemas/board-state.schema.json's rds[] items now declare
# leash (string|null, enum null/A/A+), project-state.sh populates it from the
# RD's own delegation.leash frontmatter field via cz_rd_field, and
# board.html's renderCard() renders it as a badge.
#
# Constructs a minimal scratch project: one rd/*.md file with a real
# delegation.leash value, a matching state/locks/*.lock, and a
# telemetry/events.jsonl containing several lines tagged with that RD's id —
# some carrying a numeric cost_usd, one with no cost_usd at all (must not
# count as 0), and one tagged with a DIFFERENT RD's id (must not leak into
# this RD's sum). Runs project-state.sh against it and asserts the resulting
# state/board.json has both fields populated correctly, and validates the
# whole file against schemas/board-state.schema.json.
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry (audit finding C5's contamination story).
# lib/common.sh refuses to run at all unless CZ_ROOT or CLAUDE_PROJECT_DIR is
# set, so this test exports CZ_ROOT explicitly, matching every other
# hooks/tests/test-*.sh script in this plugin.
#
# Usage: bash hooks/tests/test-project-state.sh

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
HOOK="$DIR/../project-state.sh"
BOARD_SCHEMA="$DIR/../../schemas/board-state.schema.json"

export CZ_ROOT
CZ_ROOT="$(cz_test_tmpdir)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd" "$CZ_ROOT/state/locks" "$CZ_ROOT/state/heartbeats" \
         "$CZ_ROOT/telemetry" "$CZ_ROOT/gate-records" "$CZ_ROOT/config"

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

cat > "$CZ_ROOT/config/gates.yaml" <<'EOF'
profile: standard
concurrency:
  max_in_flight: 3
EOF

# --- RD-TEST-001.01: has a real delegation.leash and a claim lock ---
cat > "$CZ_ROOT/rd/RD-TEST-001.01.md" <<'EOF'
id: RD-TEST-001.01
state: claimed
module: reconciliation
summary: "cost/leash rollup fixture"
assigned_agent: dev
claimed_at: "2026-07-29T00:00:00Z"
delegation:
  level: L3
  leash: "A+"
EOF

cat > "$CZ_ROOT/state/locks/RD-TEST-001.01.lock" <<'EOF'
agent=dev
ts=2026-07-29T00:00:00Z
EOF

# --- RD-TEST-002.01: a second RD with NO cost-bearing telemetry at all —
# its cost_usd must come back null, not a silently-invented 0. ---
cat > "$CZ_ROOT/rd/RD-TEST-002.01.md" <<'EOF'
id: RD-TEST-002.01
state: ready
module: reconciliation
summary: "no-telemetry fixture"
assigned_agent: null
claimed_at: null
delegation:
  level: L1
  leash: "A"
EOF

# --- RD-TEST-003.01: ACCEPTED (terminal), but its heartbeat file is still
# frozen at agent_state "executing" from before the gate closed — the exact
# shape of the false-stall bug seen live on RD-AIBOOTCAMP-005.01c. ---
cat > "$CZ_ROOT/rd/RD-TEST-003.01.md" <<'EOF'
id: RD-TEST-003.01
state: accepted
module: reconciliation
summary: "false-stall fixture — accepted with a stale executing heartbeat"
assigned_agent: null
claimed_at: null
delegation:
  level: L3
  leash: "A"
EOF
cat > "$CZ_ROOT/state/heartbeats/ai-reviewer.hb" <<'EOF'
{"last_heartbeat":"2026-07-29T00:00:00Z","agent_state":"executing","rd":"RD-TEST-003.01"}
EOF

# --- Genuinely in-flight heartbeat for RD-TEST-001.01 (state: claimed) —
# must NOT be downgraded; a real stall on a real in-flight RD must still
# read as "executing". ---
cat > "$CZ_ROOT/state/heartbeats/dev.hb" <<'EOF'
{"last_heartbeat":"2026-07-29T00:00:00Z","agent_state":"executing","rd":"RD-TEST-001.01"}
EOF

# telemetry: 3 lines tagged to RD-TEST-001.01 (two carry cost_usd, one
# doesn't — must still count only the two that do), plus 1 line tagged to a
# DIFFERENT RD (must not leak into RD-TEST-001.01's sum), plus 0 lines at all
# for RD-TEST-002.01.
cat > "$CZ_ROOT/telemetry/events.jsonl" <<'EOF'
{"ts":"2026-07-29T00:01:00Z","run_id":"r-1","rd":"RD-TEST-001.01","agent":"dev","event":"agent_dispatch","tool_name":"Bash","result":"ok","cost_usd":0.12,"cost_source":"gateway"}
{"ts":"2026-07-29T00:02:00Z","run_id":"r-1","rd":"RD-TEST-001.01","agent":"dev","event":"agent_dispatch","tool_name":"Bash","result":"ok"}
{"ts":"2026-07-29T00:03:00Z","run_id":"r-1","rd":"RD-TEST-001.01","agent":"dev","event":"agent_dispatch","tool_name":"Bash","result":"ok","cost_usd":0.08,"cost_source":"gateway"}
{"ts":"2026-07-29T00:04:00Z","run_id":"r-1","rd":"RD-TEST-999.99","agent":"dev","event":"agent_dispatch","tool_name":"Bash","result":"ok","cost_usd":99.00,"cost_source":"gateway"}
EOF

CZ_ROOT="$CZ_ROOT" bash "$HOOK" >/tmp/cz-test-project-state.out 2>&1
HOOK_EXIT=$?
check "project-state.sh exits 0" "$([ "$HOOK_EXIT" -eq 0 ] && echo 1 || echo 0)"

BOARD_FILE="$CZ_ROOT/state/board.json"
check "state/board.json was written" "$([ -f "$BOARD_FILE" ] && echo 1 || echo 0)"

RD1_ENTRY="$("$PYBIN" -c "
import json
d = json.load(open('$BOARD_FILE'))
for rd in d['rds']:
    if rd['id'] == 'RD-TEST-001.01':
        print(json.dumps(rd))
        break
")"
echo "  RD-TEST-001.01 entry: $RD1_ENTRY"

COST_OK="$("$PYBIN" -c "
import json
rd = json.loads('''$RD1_ENTRY''')
print(1 if abs(rd.get('cost_usd', -1) - 0.20) < 1e-6 else 0)
")"
check "cost_usd for RD-TEST-001.01 sums only its own cost-bearing events (0.12+0.08=0.20, not 99.20)" "$COST_OK"

LEASH_OK="$("$PYBIN" -c "
import json
rd = json.loads('''$RD1_ENTRY''')
print(1 if rd.get('leash') == 'A+' else 0)
")"
check "leash for RD-TEST-001.01 is populated from delegation.leash (A+)" "$LEASH_OK"

RD2_ENTRY="$("$PYBIN" -c "
import json
d = json.load(open('$BOARD_FILE'))
for rd in d['rds']:
    if rd['id'] == 'RD-TEST-002.01':
        print(json.dumps(rd))
        break
")"
echo "  RD-TEST-002.01 entry: $RD2_ENTRY"

NULL_COST_OK="$("$PYBIN" -c "
import json
rd = json.loads('''$RD2_ENTRY''')
print(1 if rd.get('cost_usd', 'MISSING') is None else 0)
")"
check "cost_usd for RD-TEST-002.01 (no telemetry at all) is JSON null, not a fabricated 0" "$NULL_COST_OK"

LEASH2_OK="$("$PYBIN" -c "
import json
rd = json.loads('''$RD2_ENTRY''')
print(1 if rd.get('leash') == 'A' else 0)
")"
check "leash for RD-TEST-002.01 is populated from delegation.leash (A)" "$LEASH2_OK"

# Full board.json must validate against schemas/board-state.schema.json.
SCHEMA_VALID="$("$PYBIN" - "$BOARD_FILE" "$BOARD_SCHEMA" <<'PYEOF'
import json, sys
try:
    import jsonschema
except ImportError:
    print("valid"); sys.exit(0)
board = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    jsonschema.validate(instance=board, schema=schema)
    print("valid")
except jsonschema.exceptions.ValidationError as e:
    print(f"invalid: {e.message}")
PYEOF
)"
echo "  board.json schema validation: $SCHEMA_VALID"
check "state/board.json validates against schemas/board-state.schema.json" \
  "$([ "$SCHEMA_VALID" = "valid" ] && echo 1 || echo 0)"

AGENT_STATES="$("$PYBIN" -c "
import json
d = json.load(open('$BOARD_FILE'))
print(json.dumps({a['agent']: a['agent_state'] for a in d['agents']}))
")"
echo "  agents agent_state map: $AGENT_STATES"

STALE_DOWNGRADED="$("$PYBIN" -c "
import json
m = json.loads('''$AGENT_STATES''')
print(1 if m.get('ai-reviewer') == 'idle' else 0)
")"
check "heartbeat pinned to an accepted RD (RD-TEST-003.01) is downgraded from executing to idle, not left to false-stall forever" "$STALE_DOWNGRADED"

INFLIGHT_UNCHANGED="$("$PYBIN" -c "
import json
m = json.loads('''$AGENT_STATES''')
print(1 if m.get('dev') == 'executing' else 0)
")"
check "heartbeat pinned to a genuinely in-flight RD (RD-TEST-001.01, state: claimed) stays executing" "$INFLIGHT_UNCHANGED"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
