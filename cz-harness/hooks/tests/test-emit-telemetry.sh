#!/usr/bin/env bash
# Self-test for hooks/emit-telemetry.sh (audit finding C7).
#
# C7: real logged events were a bare "who called what tool" record with
# "rd":null and "agent":"unknown" as fallback sentinels that VIOLATED
# telemetry-event.schema.json outright (the schema's rd field only allowed a
# ^RD-...$ string, no null; the agent enum had no "unknown" member), and the
# hook's own "heartbeat_transition" event name wasn't in the schema's event
# enum at all. The fix: (a) emit-telemetry.sh already reuses the same
# lock-based identity-resolution pattern as guard-red-before-green.sh/
# guard-rd-freeze.sh/detect-hazard.sh (cz_extract_rd_id -> cz_lock_agent_for_rd
# -> cz_rd_field assigned_agent -> cz_sole_lock_agent/cz_sole_lock_rd), so a
# real, active RD claim resolves to a REAL rd id and REAL agent name, not the
# fallback sentinels; (b) the event name is now "agent_heartbeat" (an
# existing schema enum value) instead of the unlisted "heartbeat_transition";
# (c) the schema itself now explicitly allows the fallback sentinels
# ("rd":null, "agent":"unknown") for the genuinely-no-context case, so they
# are no longer silent violations either way.
#
# This script proves the REAL-CONTEXT path: with an active lock held for a
# real RD, the emitted agent_dispatch (and agent_heartbeat, on first tick)
# events carry that RD's real id and real agent — never the null/"unknown"
# fallback — and validates every emitted line against
# schemas/telemetry-event.schema.json using Python's jsonschema.
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry (audit finding C5's contamination story).
# lib/common.sh refuses to run at all unless CZ_ROOT or CLAUDE_PROJECT_DIR is
# set, so this test exports CZ_ROOT explicitly, matching every other
# hooks/tests/test-*.sh script in this plugin.
#
# Usage: bash hooks/tests/test-emit-telemetry.sh

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
HOOK="$DIR/../emit-telemetry.sh"
SCHEMA="$DIR/../../schemas/telemetry-event.schema.json"

export CZ_ROOT
CZ_ROOT="$(cz_test_tmpdir)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/state/locks" "$CZ_ROOT/state/heartbeats" "$CZ_ROOT/telemetry" "$CZ_ROOT/rd"

TELEMETRY_FILE="$CZ_ROOT/telemetry/events.jsonl"

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

# validate_last_line_against_schema: pulls the last line of events.jsonl and
# validates it against telemetry-event.schema.json. Prints "valid" or
# "invalid: <reason>".
validate_last_line() {
  "$PYBIN" - "$TELEMETRY_FILE" "$SCHEMA" <<'PYEOF'
import json, sys
try:
    import jsonschema
except ImportError:
    print("valid")  # no validator available; caller falls back to manual checks
    sys.exit(0)
events_file, schema_file = sys.argv[1], sys.argv[2]
with open(events_file) as f:
    lines = [l for l in f if l.strip()]
if not lines:
    print("invalid: no lines in telemetry file")
    sys.exit(0)
last = json.loads(lines[-1])
schema = json.load(open(schema_file))
try:
    jsonschema.validate(instance=last, schema=schema)
    print("valid")
except jsonschema.exceptions.ValidationError as e:
    print(f"invalid: {e.message}")
PYEOF
}

# --- Case 1: exactly one active lock, real RD, real agent, no RD id in the
# tool call's own text -> sole-lock fallback must resolve BOTH rd and agent
# to real values (not null/"unknown"). ---
rm -f "$TELEMETRY_FILE"
cat > "$CZ_ROOT/state/locks/RD-TEST-001.01.lock" <<'EOF'
agent=dev
ts=2026-07-29T00:00:00Z
EOF

PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
printf '%s' "$PAYLOAD" | CZ_ROOT="$CZ_ROOT" bash "$HOOK" >/tmp/cz-test-emit-telemetry.out 2>&1
HOOK_EXIT=$?
check "hook exits 0 on a normal tool call" "$([ "$HOOK_EXIT" -eq 0 ] && echo 1 || echo 0)"

LAST_LINE="$(tail -1 "$TELEMETRY_FILE" 2>/dev/null || true)"
echo "  last event: $LAST_LINE"

RD_OK=0
echo "$LAST_LINE" | grep -q '"rd":"RD-TEST-001\.01"' && RD_OK=1
check "rd resolves to the real active RD id (not null)" "$RD_OK"

AGENT_OK=0
echo "$LAST_LINE" | grep -q '"agent":"dev"' && AGENT_OK=1
check "agent resolves to the real lock-holding agent (not \"unknown\")" "$AGENT_OK"

EVENT_OK=0
echo "$LAST_LINE" | grep -q '"event":"agent_dispatch"' && EVENT_OK=1
check "event name is agent_dispatch (a real schema enum member)" "$EVENT_OK"

VALIDATION="$(validate_last_line)"
echo "  schema validation: $VALIDATION"
check "emitted agent_dispatch event validates against telemetry-event.schema.json" \
  "$([ "$VALIDATION" = "valid" ] && echo 1 || echo 0)"

# First tick for "dev" -> a first-heartbeat agent_heartbeat event must also
# have been appended (PREV_RD had no prior .hb file), using the real
# schema-listed event name, not the old unlisted "heartbeat_transition".
HEARTBEAT_LINE="$(grep '"event":"agent_heartbeat"' "$TELEMETRY_FILE" | tail -1 || true)"
echo "  heartbeat event: $HEARTBEAT_LINE"
HB_OK=0
[ -n "$HEARTBEAT_LINE" ] && echo "$HEARTBEAT_LINE" | grep -q '"rd":"RD-TEST-001\.01"' && HB_OK=1
check "agent_heartbeat event fired on first tick with the real RD id" "$HB_OK"

HB_VALID="$("$PYBIN" - "$SCHEMA" <<PYEOF
import json, sys
try:
    import jsonschema
except ImportError:
    print("valid"); sys.exit(0)
line = json.loads('''$HEARTBEAT_LINE''')
schema = json.load(open(sys.argv[1]))
try:
    jsonschema.validate(instance=line, schema=schema)
    print("valid")
except jsonschema.exceptions.ValidationError as e:
    print(f"invalid: {e.message}")
PYEOF
)"
echo "  heartbeat schema validation: $HB_VALID"
check "agent_heartbeat event validates against the schema" \
  "$([ "$HB_VALID" = "valid" ] && echo 1 || echo 0)"

check "no stray \"heartbeat_transition\" (old, unlisted name) was emitted" \
  "$([ -z "$(grep '\"event\":\"heartbeat_transition\"' "$TELEMETRY_FILE" || true)" ] && echo 1 || echo 0)"

# --- Case 2: no lock at all (phase-level work, e.g. ba/sa doing project-level
# phases 0-6/10) -> rd/agent legitimately unresolvable. Must emit real JSON
# null / "unknown" and STILL validate against the schema (the schema now
# explicitly allows this fallback rather than silently permitting a
# violation). ---
rm -f "$TELEMETRY_FILE" "$CZ_ROOT/state/locks/RD-TEST-001.01.lock"
rm -f "$CZ_ROOT"/state/heartbeats/*.hb 2>/dev/null || true

PAYLOAD2='{"tool_name":"Read","tool_input":{"file_path":"deliverables/SCOPE-PB01.md"}}'
printf '%s' "$PAYLOAD2" | CZ_ROOT="$CZ_ROOT" bash "$HOOK" >/tmp/cz-test-emit-telemetry-2.out 2>&1

LAST_LINE2="$(tail -1 "$TELEMETRY_FILE" 2>/dev/null || true)"
echo "  last event (no-context case): $LAST_LINE2"

NULL_RD_OK=0
echo "$LAST_LINE2" | grep -q '"rd":null' && NULL_RD_OK=1
check "with no active claim, rd is real JSON null (not the string \"null\")" "$NULL_RD_OK"

UNKNOWN_AGENT_OK=0
echo "$LAST_LINE2" | grep -q '"agent":"unknown"' && UNKNOWN_AGENT_OK=1
check "with no active claim, agent is \"unknown\"" "$UNKNOWN_AGENT_OK"

VALIDATION2="$(validate_last_line)"
echo "  schema validation (no-context case): $VALIDATION2"
check "the no-context event (rd:null, agent:unknown) still validates against the schema" \
  "$([ "$VALIDATION2" = "valid" ] && echo 1 || echo 0)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
