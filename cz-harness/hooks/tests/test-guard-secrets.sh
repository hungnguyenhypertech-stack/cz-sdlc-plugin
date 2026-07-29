#!/usr/bin/env bash
# Self-test for hooks/guard-secrets.sh (audit finding C2).
#
# Not part of the RD-facing tests/** convention (that's reserved for RDs of a
# project *using* cz-harness — see agents/test-designer.md's Write(tests/**)
# grant). This lives under hooks/tests/ instead, colocated with the hook it
# tests, so it is never confused with or claimed by that convention.
#
# Regression coverage for C2: guard-secrets.sh used to fail OPEN on the
# private-key pattern because `grep "$pat"` parsed a pattern starting with
# `-----` as flags instead of pattern text. The fix was `grep -e "$pat"`.
# This script proves that fix holds, proves the other five deny patterns are
# each independently caught (not just assumed via a shared code path), and
# proves the fix didn't turn "content starts with a dash" into a false
# positive.
#
# Usage: bash hooks/tests/test-guard-secrets.sh
# Exit 0 if every case passes, exit 1 (with FAIL lines on stderr) otherwise.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-secrets.sh"

# lib/common.sh (sourced by every hook) now refuses to run at all unless
# CZ_ROOT or CLAUDE_PROJECT_DIR is set (audit finding C5 — it used to fall
# back to $(pwd) silently, which is what caused C5's contamination in the
# first place). This hook doesn't read anything under CZ_ROOT, but still
# needs one set to get past that guard; an empty scratch dir is fine.
export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT

pass_count=0
fail_count=0

# run_case <description> <content> <expected: deny|allow>
run_case() {
  local desc="$1" content="$2" expected="$3"
  # Escape backslashes and double-quotes so $content is safe as a JSON string
  # value, then collapse any real newline into a literal \n so the payload
  # stays one line — real Claude Code hook input is compact single-line JSON,
  # and guard-secrets.sh's sed-based "content" extraction is line-oriented
  # (a raw embedded newline would split the field across lines and the
  # extraction would find nothing at all, independent of the C2 fix this
  # script targets).
  # Portable multi-line-to-literal-\n join: the classic `sed ':a;N;$!ba'`
  # idiom needs real newlines between sed commands under BSD sed, not
  # semicolons — using it here would reintroduce exactly the GNU/BSD
  # portability bug class this whole audit pass is fixing. awk's per-line
  # loop is portable across both.
  local escaped
  escaped="$(printf '%s' "$content" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{printf "%s%s", (NR==1?"":"\\n"), $0}')"
  local payload
  payload="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"scratch.txt\",\"content\":\"$escaped\"}}"

  local actual
  if printf '%s' "$payload" | bash "$HOOK" >/tmp/cz-test-guard-secrets.out 2>&1; then
    actual="allow"
  else
    actual="deny"
  fi

  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc (expected $expected, got $actual)"
    pass_count=$((pass_count+1))
  else
    echo "FAIL: $desc (expected $expected, got $actual)" >&2
    fail_count=$((fail_count+1))
  fi
}

# --- The exact C2 regression case ---
run_case "RSA private key block -> deny" \
  "-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN
-----END RSA PRIVATE KEY-----" deny

# --- Same alternation, each header independently proven caught ---
run_case "EC private key block -> deny" \
  "-----BEGIN EC PRIVATE KEY-----MHcCAQEEIB1234567890abcdef-----END EC PRIVATE KEY-----" deny

run_case "OPENSSH private key block -> deny" \
  "-----BEGIN OPENSSH PRIVATE KEY-----b3BlbnNzaC1rZXktdjEAAAAA-----END OPENSSH PRIVATE KEY-----" deny

run_case "DSA private key block -> deny" \
  "-----BEGIN DSA PRIVATE KEY-----MIIBuwIBAAKBgQD1234567890-----END DSA PRIVATE KEY-----" deny

# --- One case per remaining deny pattern ---
run_case "AWS access key -> deny" \
  "aws_access_key = AKIAABCDEFGHIJKLMNOP" deny

# (Value deliberately unquoted: a quoted value would embed literal escaped
# quotes via this script's own JSON-escaping, which trips guard-secrets.sh's
# separately-flagged JSON-extraction fragility rather than exercising the
# C2 fix under test — see the audit's C2 plan §4 "not a sign-off item" note.)
run_case "api_key= assignment -> deny" \
  "api_key=AbCdEfGh12345678IjKlMnOp" deny

run_case "password= assignment -> deny" \
  "password=SuperSecret123" deny

run_case "sk- style secret key -> deny" \
  "token: sk-abcdefghij1234567890ABCDEFGHIJ" deny

run_case "ghp_ GitHub PAT -> deny" \
  "GITHUB_TOKEN=ghp_abcdefghij1234567890abcdefghij1234" deny

# --- Negative controls ---
run_case "ordinary benign content -> allow" \
  "def add(a, b):\n    return a + b" allow

run_case "leading-dash markdown frontmatter delimiter -> allow" \
  "--- frontmatter ---\ntitle: hello\n---" allow

run_case "leading-dash CLI usage string -> allow" \
  "usage: mytool --verbose --output foo.txt" allow

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
