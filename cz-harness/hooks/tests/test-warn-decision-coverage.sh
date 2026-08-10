#!/usr/bin/env bash
# Self-test for hooks/warn-decision-coverage.sh.
#
# Regression coverage: /cz:health-check (2026-08-10, AIBOOTCAMP) found two
# hazard:HIGH modules whose XSS/DOM-safety rationale existed only as ARCH.md
# prose, not at either canonical decision-record location (a dedicated
# deliverables/adr/*.md file, or a #### ADR-NNN heading in that module's own
# ARCH.md section) — invisible until a manual audit read every module
# section by hand. This script proves the hook flags a hazard:HIGH module
# with neither location present, stays silent once either location exists,
# dedupes per module, and ignores non-HIGH modules entirely.
#
# Uses an isolated scratch CZ_ROOT — never touches the real plugin's state
# (see audit finding C5 about exactly that kind of contamination).
#
# Usage: bash hooks/tests/test-warn-decision-coverage.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../warn-decision-coverage.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/deliverables"

RISK_FILE="$CZ_ROOT/deliverables/RISK-TEST.md"
ARCH_FILE="$CZ_ROOT/deliverables/ARCH-TEST.md"

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
  local payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$RISK_FILE\"}}"
  CZ_ROOT="$CZ_ROOT" bash -c "printf '%s' '$payload' | '$HOOK'" >/dev/null 2>&1
}

gap_count() {
  [ -f "$CZ_ROOT/telemetry/events.jsonl" ] || { echo 0; return; }
  grep -c '"event":"decision_gap"' "$CZ_ROOT/telemetry/events.jsonl"
}

cat > "$RISK_FILE" <<'EOF'
## 1. Module risk register

### 1.1 `safe-module` — hazard: **LOW** — leash: A

no notable risk.

### 1.2 `risky-module` — hazard: **HIGH** — leash: B

renders untrusted content.
EOF

# Case A: no ARCH.md at all, no adr/ dir -> flagged
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "hazard:HIGH module, no ARCH.md, no adr/ dir -> flagged" "1" "$(gap_count)"

# Case B: re-run, same state -> deduped
run_hook
check "re-run, same gap -> deduped" "1" "$(gap_count)"

# Case C: ARCH.md exists but the module's section has no ADR heading -> still flagged
cat > "$ARCH_FILE" <<'EOF'
## 1. `safe-module` (layer 0)

Some prose, no ADR.

## 2. `risky-module` (layer 1)

Some prose about risky-module, still no ADR heading here.

## 3. `unrelated-module` (layer 1)
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "ARCH.md present, module section has no ADR heading -> still flagged" "1" "$(gap_count)"

# Case D: module's own ARCH section gets an ADR heading -> silent
cat > "$ARCH_FILE" <<'EOF'
## 1. `safe-module` (layer 0)

Some prose, no ADR.

## 2. `risky-module` (layer 1)

#### ADR-009 — DOM-safety / untrusted-content rendering decision

Escape everything before insertion.

## 3. `unrelated-module` (layer 1)
EOF
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "ADR heading now present in module's section -> silent" "0" "$(gap_count)"

# Case E: no ADR heading, but a deliverables/adr/*.md file exists -> silent
cat > "$ARCH_FILE" <<'EOF'
## 2. `risky-module` (layer 1)

Still no ADR heading here.
EOF
mkdir -p "$CZ_ROOT/deliverables/adr"
echo "# ADR-009" > "$CZ_ROOT/deliverables/adr/ADR-009-dom-safety.md"
rm -f "$CZ_ROOT/telemetry/events.jsonl"
run_hook
check "deliverables/adr/*.md file exists -> silent" "0" "$(gap_count)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
