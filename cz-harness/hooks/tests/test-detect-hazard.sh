#!/usr/bin/env bash
# Self-test for hooks/detect-hazard.sh (audit finding C1).
#
# Regression coverage: detect-hazard.sh used to never escalate anything,
# because its glob-cleanup sed pattern (`s/^-\s*"?//; s/"?$//`) relied on
# `\s` (unsupported by this platform's BSD sed) and an anchor that didn't
# account for the 2-space YAML indent in front of each `- "glob"` line — so
# every hazard_paths entry survived as unmatched garbage and no path ever
# tripped it. The fix uses `[[:space:]]` instead of `\s` and accounts for
# leading indentation. This script proves escalation now actually fires for
# every configured hazard path, and stays silent for a non-hazard path.
#
# Uses an isolated CZ_ROOT under the scratch dir — never touches the real
# plugin's own state/telemetry (see audit finding C5 about exactly that kind
# of contamination).
#
# Usage: bash hooks/tests/test-detect-hazard.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../detect-hazard.sh"
HAZARD_YAML="$DIR/../../config/hazard-paths.yaml"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/config"
cp "$HAZARD_YAML" "$SCRATCH/config/hazard-paths.yaml"

pass_count=0
fail_count=0

# run_case <description> <file_path> <expected: escalate|silent>
run_case() {
  local desc="$1" file_path="$2" expected="$3"
  rm -f "$SCRATCH/telemetry/events.jsonl"
  local payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$file_path\"}}"
  CZ_ROOT="$SCRATCH" bash -c "printf '%s' '$payload' | '$HOOK'" >/dev/null 2>&1

  local actual="silent"
  if [ -f "$SCRATCH/telemetry/events.jsonl" ] && grep -q '"event":"hazard_escalation"' "$SCRATCH/telemetry/events.jsonl"; then
    actual="escalate"
  fi

  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc (expected $expected, got $actual)"
    pass_count=$((pass_count+1))
  else
    echo "FAIL: $desc (expected $expected, got $actual)" >&2
    fail_count=$((fail_count+1))
  fi
}

# One case per configured hazard_paths glob (config/hazard-paths.yaml, §8.4)
run_case "**/auth/**"              "src/auth/login.py"              escalate
run_case "**/permissions/**"       "src/permissions/roles.py"       escalate
run_case "**/migrations/**"        "db/migrations/0001_init.sql"    escalate
run_case "**/*secret*"             "config/my_secret_thing.txt"     escalate
run_case "**/payment/**"           "src/payment/charge.py"          escalate
run_case "**/pii/**"               "src/pii/export.py"              escalate
run_case ".github/workflows/**"    ".github/workflows/deploy.yml"   escalate

# Negative control: an ordinary, non-hazard path must stay silent
run_case "non-hazard path"         "src/reporting/refresh.py"       silent

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
