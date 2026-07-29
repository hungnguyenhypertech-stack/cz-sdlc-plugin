#!/usr/bin/env bash
# Self-test for hooks/guard-role-boundaries.sh's telemetry append-only check
# (audit finding M3).
#
# M3: the WHO-may-write check in guard-role-boundaries.sh (only agentops/hook
# may write telemetry/events.jsonl) says nothing about WHETHER the write is
# actually append-only — nothing previously stopped agentops itself from
# truncating or rewriting telemetry history via a direct Write tool call.
# The fix added a byte-prefix check: the file's CURRENT on-disk content (still
# the OLD content at PreToolUse time, since PreToolUse fires BEFORE the write
# lands) must be a strict prefix of the NEW content the tool call would write.
#
# Not part of the RD-facing tests/** convention — see test-guard-secrets.sh's
# header for why these live under hooks/tests/ instead.
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state/telemetry (audit finding C5's contamination story).
# lib/common.sh now refuses to run at all unless CZ_ROOT or
# CLAUDE_PROJECT_DIR is set, so this test exports CZ_ROOT explicitly.
#
# Usage: bash hooks/tests/test-guard-role-boundaries-telemetry.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-role-boundaries.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/telemetry" "$CZ_ROOT/state/locks"

TELEMETRY_FILE="$CZ_ROOT/telemetry/events.jsonl"

# A single active lock for "agentops" so guard-role-boundaries.sh's identity
# fallback (cz_sole_lock_agent, see lib/common.sh's "Identity fallback"
# section) resolves ACTOR=agentops without needing CZ_ACTING_AGENT set —
# exactly like every other real invocation of this hook in this plugin.
cat > "$CZ_ROOT/state/locks/RD-TEST-001.01.lock" <<'EOF'
agent=agentops
ts=2026-07-29T00:00:00Z
EOF

pass_count=0
fail_count=0

# json_escape_content <raw-content>: mirrors test-guard-secrets.sh's payload
# builder — escapes backslashes/quotes, then joins real newlines into literal
# \n so the payload stays valid single-line JSON (real Claude Code hook input
# is compact single-line JSON; guard-role-boundaries.sh's content extraction
# is line-oriented).
json_escape_content() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{printf "%s%s", (NR==1?"":"\\n"), $0}'
}

# run_case <description> <existing-content-or-""> <new-content> <expected: allow|deny>
run_case() {
  local desc="$1" existing="$2" new_content="$3" expected="$4"
  rm -f "$TELEMETRY_FILE"
  if [ -n "$existing" ]; then
    printf '%s' "$existing" > "$TELEMETRY_FILE"
  fi

  local escaped payload
  escaped="$(json_escape_content "$new_content")"
  payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TELEMETRY_FILE\",\"content\":\"$escaped\"}}"

  local actual
  if printf '%s' "$payload" | bash "$HOOK" >/tmp/cz-test-guard-role-boundaries-telemetry.out 2>&1; then
    actual="allow"
  else
    actual="deny"
  fi

  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc (expected $expected, got $actual)"
    pass_count=$((pass_count+1))
  else
    echo "FAIL: $desc (expected $expected, got $actual)" >&2
    echo "  --- hook output ---" >&2
    sed 's/^/  /' /tmp/cz-test-guard-role-boundaries-telemetry.out >&2
    fail_count=$((fail_count+1))
  fi
}

# --- Case 1: file doesn't exist yet -> first write, any content is fine ---
run_case "telemetry file absent -> first write allowed" \
  "" \
  "line1
line2
" \
  allow

# --- Case 2: true append (existing content is a strict prefix) -> allow ---
run_case "existing=line1, new=line1+line2 (true append) -> allow" \
  "line1
" \
  "line1
line2
" \
  allow

# --- Case 3: truncation (new content is shorter, drops line2) -> deny ---
run_case "existing=line1+line2, new=line1 only (truncation) -> deny" \
  "line1
line2
" \
  "line1
" \
  deny

# --- Case 4: rewrite (same length-ish, but an existing line changed) -> deny ---
run_case "existing=line1+line2, new=line1+MODIFIED (rewrite, not append) -> deny" \
  "line1
line2
" \
  "line1
MODIFIED
" \
  deny

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
