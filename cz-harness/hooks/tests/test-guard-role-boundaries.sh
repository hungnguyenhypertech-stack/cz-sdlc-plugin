#!/usr/bin/env bash
# Self-test for hooks/guard-role-boundaries.sh's WHO-may-write role checks
# (plan §8.1 anti-collusion invariants). Not the telemetry byte-prefix
# sub-check — that's already covered by test-guard-role-boundaries-telemetry.sh;
# this file focuses on dev/tests, test-designer/src, reviews/**, gate-records/**
# human_approved forgery, config/gates.yaml, and sub-pm's approval-verb ban.
#
# Uses CZ_ACTING_AGENT directly to set ACTOR (guard-role-boundaries.sh checks
# this env var first, before falling back to lock-file inference — see
# lib/common.sh's "Identity fallback" section and this hook's own header).
#
# *** Known bug documented here, NOT fixed (out of scope for this test file
# per its own brief — see the "KNOWN BUG" cases below) ***:
# guard-role-boundaries.sh's top-level CONTENT extraction (line 11):
#   grep -o '"content"[[:space:]]*:[[:space:]]*"[^"]*"'
# stops at the FIRST raw `"` byte. A real Write tool_input's content field is
# JSON-escaped (every literal `"` inside the file being written becomes the
# two-byte sequence \"), so for ANY realistic JSON content — which is exactly
# the shape of a real gate-records/*.json file — this extraction truncates
# at the very first escaped quote, almost always before "human_approved" (or
# "approved") ever appears in the captured text. The human_approved forgery
# check (line 54) and the sub-pm approval-verb ban (line 128) both read from
# this same broken CONTENT variable, so both are effectively dead code
# against realistic input. The file's OWN M3 audit fix already shows the
# correct fix exists in this codebase: line 104's
#   grep -oE '"content"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"'
# (the telemetry append-only check) correctly treats \" as an escaped
# character rather than a terminator — that same pattern was just never
# applied to the shared CONTENT variable at the top of the file. Confirmed
# by direct execution, not just reading: an ai-reviewer Write of
# {"content":"{\"human_approved\": true}"} to gate-records/** currently
# exits 0 (allowed) instead of denied.
#
# Usage: bash hooks/tests/test-guard-role-boundaries.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-role-boundaries.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/state/locks" "$CZ_ROOT/telemetry" "$CZ_ROOT/rd"

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

# json_escape_content: mirrors test-guard-role-boundaries-telemetry.sh's
# payload builder — real content, properly JSON-escaped, exactly as a real
# Claude Code Write tool_input would encode it.
json_escape_content() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{printf "%s%s", (NR==1?"":"\\n"), $0}'
}

# run_write <agent> <file_path-suffix> <content>: prints allow/deny.
run_write() {
  local agent="$1" file_suffix="$2" content="$3" escaped payload
  escaped="$(json_escape_content "$content")"
  payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$CZ_ROOT/$file_suffix\",\"content\":\"$escaped\"}}"
  if printf '%s' "$payload" | CZ_ROOT="$CZ_ROOT" CZ_ACTING_AGENT="$agent" bash "$HOOK" \
      >/tmp/cz-test-guard-role-boundaries.out 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# --- dev may not write tests/** -------------------------------------------
check "dev writing tests/** -> deny" "deny" \
  "$(run_write dev "tests/reconciliation/test_refresh.py" "def test_x(): pass")"
check "test-designer writing tests/** -> allow (control)" "allow" \
  "$(run_write test-designer "tests/reconciliation/test_refresh.py" "def test_x(): pass")"

# --- test-designer may not write src/** -----------------------------------
check "test-designer writing src/** -> deny" "deny" \
  "$(run_write test-designer "src/reconciliation/refresh_guard.py" "def refresh(): pass")"
check "dev writing src/** -> allow (control)" "allow" \
  "$(run_write dev "src/reconciliation/refresh_guard.py" "def refresh(): pass")"

# --- only ai-reviewer/sec-reviewer/human may write reviews/** -------------
check "dev writing deliverables/reviews/** -> deny" "deny" \
  "$(run_write dev "deliverables/reviews/RD-TEST-001.01-review.md" "looks fine to me")"
check "ai-reviewer writing deliverables/reviews/** -> allow" "allow" \
  "$(run_write ai-reviewer "deliverables/reviews/RD-TEST-001.01-review.md" "AI review notes")"
check "sec-reviewer writing deliverables/reviews/security/** -> allow" "allow" \
  "$(run_write sec-reviewer "deliverables/reviews/security/RD-TEST-001.01-sec.md" "security review notes")"
check "human writing deliverables/reviews/** -> allow" "allow" \
  "$(run_write human "deliverables/reviews/RD-TEST-001.01-review.md" "human override notes")"

# --- config/gates.yaml may only be written by human -----------------------
check "risk-gov writing config/gates.yaml -> deny" "deny" \
  "$(run_write risk-gov "config/gates.yaml" "profile: heavy")"
check "human writing config/gates.yaml -> allow" "allow" \
  "$(run_write human "config/gates.yaml" "profile: heavy")"

# --- gate-records/** human_approved forgery -------------------------------
# *** KNOWN BUG (documented above; see guard-role-boundaries.sh:11) ***
# This is the intended/documented behavior (only a human may set
# human_approved: true — plan §8.1 invariant 4). It currently FAILS because
# realistic escaped JSON content breaks the naive CONTENT extraction before
# "human_approved" is ever visible to the check. Left failing deliberately,
# per this task's instruction not to modify hook .sh files — this test will
# start passing automatically once guard-role-boundaries.sh:11 is fixed to
# use the same \"-aware regex already used at line 104.
check "KNOWN BUG: ai-reviewer forging human_approved:true in gate-records/** -> should deny" "deny" \
  "$(run_write ai-reviewer "gate-records/RD-TEST-001.01-gate.json" '{"decision": "approved", "human_approved": true}')"

check "human legitimately writing human_approved:true in gate-records/** -> allow" "allow" \
  "$(run_write human "gate-records/RD-TEST-001.01-gate.json" '{"decision": "approved", "human_approved": true}')"

check "ai-reviewer writing gate-records/** WITHOUT human_approved -> allow (no forgery attempted)" "allow" \
  "$(run_write ai-reviewer "gate-records/RD-TEST-001.01-gate.json" '{"decision": "pending"}')"

# --- sub-pm has no approval verb, ever, regardless of target path --------
# This path works today: no quote precedes "approved" in this content, so
# the naive CONTENT extraction is NOT truncated before the approval-verb
# regex (`approved.*true`, case-insensitive) can see it.
check "sub-pm writing src/** with unquoted 'approved ... true' text -> deny (regardless of path)" "deny" \
  "$(run_write sub-pm "src/reconciliation/refresh_guard.py" "marking this RD approved and setting the flag to true")"
check "dev writing the same unquoted approval-shaped text -> allow (only sub-pm is banned)" "allow" \
  "$(run_write dev "src/reconciliation/refresh_guard.py" "marking this RD approved and setting the flag to true")"

# *** KNOWN BUG (same root cause as above) ***
# A realistic, quoted `"approved": true` forgery from sub-pm should also be
# denied by the same belt-and-suspenders check (guard-role-boundaries.sh:128)
# — it reads the same broken CONTENT variable, so it is equally blind to
# any content containing a JSON-quoted key. Left failing deliberately, same
# reason as the gate-records case above.
check "KNOWN BUG: sub-pm writing realistic quoted {\"approved\": true} -> should deny" "deny" \
  "$(run_write sub-pm "gate-records/RD-TEST-002.01-gate.json" '{"approved": true}')"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
