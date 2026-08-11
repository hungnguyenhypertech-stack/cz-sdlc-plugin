#!/usr/bin/env bash
# Self-test for hooks/guard-state-transition.sh — the sole authority for
# RD-state edits (plan §6.1's table). Fires on */rd/*.md Write/Edit calls,
# reads CURRENT_STATE off the on-disk rd/*.md, extracts NEW_STATE from the
# incoming payload's embedded YAML `state: value` line, and denies any pair
# not in is_allowed()'s case table.
#
# One assertion per table entry (plus a sample of disallowed pairs), per
# the full case table read out of hooks/guard-state-transition.sh directly.
#
# NOTE: green->ai_review additionally requires deliverables/coverage/<rd>.md
# to exist on disk (step 9's coverage re-verification deliverable — added to
# close a real gap /cz:health-check found: a 41-RD project had zero files
# under deliverables/coverage/ despite test-designer's tool grant including
# it). *->superseded is also now a wildcard-allowed row, and superseded is a
# second terminal state alongside withdrawn. Table reflects the hook as of
# plugin commit ec8d88a ("Close six gaps /cz:health-check's own 7 dimensions
# found in a real run") / 60f0b17 (1.0.24-phase0) — re-check this table if
# the hook changes again.
#
# Uses an isolated scratch CZ_ROOT (mktemp -d) — never touches the real
# plugin's own state.
#
# Usage: bash hooks/tests/test-guard-state-transition.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/../guard-state-transition.sh"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd" "$CZ_ROOT/config" "$CZ_ROOT/deliverables/coverage"

RD_ID="RD-TEST-020.01"
RD_FILE="$CZ_ROOT/rd/$RD_ID.md"
GATES_YAML="$CZ_ROOT/config/gates.yaml"
COVERAGE_FILE="$CZ_ROOT/deliverables/coverage/$RD_ID.md"

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

# write_rd <current-state> [layer] [red_skipped]: (re)writes the on-disk RD
# file the hook reads CURRENT_STATE (and, for claimed->green, layer/
# red_skipped) from.
write_rd() {
  local state="$1" layer="${2:-0}" red_skipped="${3:-false}"
  cat > "$RD_FILE" <<EOF
id: $RD_ID
version: 1
content_hash: "sha256:ABCDEF"
state: $state
layer: $layer
red_skipped: $red_skipped
EOF
}

# write_gates <profile>: (re)writes config/gates.yaml with just enough for
# the claimed->green profile:light check.
write_gates() {
  local profile="$1"
  cat > "$GATES_YAML" <<EOF
profile: $profile
EOF
}
write_gates "standard"   # default: not light, so claimed->green stays gated

# run_transition <new-state>: builds the Write payload (file_path pointing
# at the real on-disk RD, content embedding the target YAML `state:` line —
# shape 2 in the hook's own header comment) and prints allow/deny. Real
# (unescaped) newlines inside the JSON string value are fine: the hook never
# JSON-parses the payload, it only greps/seds the raw bytes.
run_transition() {
  local new_state="$1" payload
  payload=$(cat <<PAYLOAD
{"tool_name":"Write","tool_input":{"file_path":"$RD_FILE","content":"id: $RD_ID
state: $new_state
"}}
PAYLOAD
)
  if echo "$payload" | CZ_ROOT="$CZ_ROOT" bash "$HOOK" >/tmp/cz-test-guard-state-transition.out 2>&1; then
    echo "allow"
  else
    echo "deny"
  fi
}

# assert_transition <desc> <from> <to> <expected> [layer] [red_skipped]
assert_transition() {
  local desc="$1" from="$2" to="$3" expected="$4" layer="${5:-0}" red_skipped="${6:-false}"
  write_rd "$from" "$layer" "$red_skipped"
  check "$desc" "$expected" "$(run_transition "$to")"
}

# --- Explicitly named allowed pairs ---------------------------------------
assert_transition "draft->ready allow" draft ready allow
assert_transition "claimed->red allow" claimed red allow
assert_transition "red->green allow" red green allow

# green->ai_review additionally requires deliverables/coverage/<rd>.md to
# exist (step 9's coverage re-verification deliverable) — test both sides.
rm -f "$COVERAGE_FILE"
assert_transition "green->ai_review deny: no deliverables/coverage/<rd>.md yet" green ai_review deny
echo "coverage notes" > "$COVERAGE_FILE"
assert_transition "green->ai_review allow: coverage deliverable exists" green ai_review allow
rm -f "$COVERAGE_FILE"

assert_transition "ai_review->sec_review allow" ai_review sec_review allow
assert_transition "ai_review->human_review allow" ai_review human_review allow
assert_transition "ai_review->rejected allow" ai_review rejected allow

# --- Wildcard rows: *->stale / *->blocked_hardstop / *->withdrawn --------
assert_transition "red->stale allow (any non-terminal state)" red stale allow
assert_transition "human_review->stale allow (any non-terminal state)" human_review stale allow
assert_transition "claimed->blocked_hardstop allow (any state)" claimed blocked_hardstop allow
assert_transition "green->blocked_hardstop allow (any state)" green blocked_hardstop allow
assert_transition "ready->withdrawn allow (any state, human descope)" ready withdrawn allow
assert_transition "red->withdrawn allow (any state, human descope)" red withdrawn allow
assert_transition "ready->superseded allow (any state, replaced by a successor RD)" ready superseded allow
assert_transition "claimed->superseded allow (any state, replaced by a successor RD)" claimed superseded allow

# --- blocked_hardstop->* (recovery) ---------------------------------------
assert_transition "blocked_hardstop->red allow (recovery)" blocked_hardstop red allow
assert_transition "blocked_hardstop->claimed allow (recovery)" blocked_hardstop claimed allow
assert_transition "blocked_hardstop->stale allow (recovery)" blocked_hardstop stale allow

# --- A sampling of other explicitly-listed rows ---------------------------
assert_transition "draft->blocked_dep allow" draft blocked_dep allow
assert_transition "blocked_dep->ready allow" blocked_dep ready allow
assert_transition "ready->claimed allow" ready claimed allow
assert_transition "claimed->ready allow" claimed ready allow
assert_transition "sec_review->human_review allow" sec_review human_review allow
assert_transition "sec_review->rejected allow" sec_review rejected allow
assert_transition "human_review->accepted allow" human_review accepted allow
assert_transition "human_review->rejected allow" human_review rejected allow
assert_transition "rejected->red allow" rejected red allow
assert_transition "stale->red allow" stale red allow
assert_transition "stale->ready allow" stale ready allow
assert_transition "accepted->stale allow" accepted stale allow

# --- claimed->green: gated on profile:light AND layer:1 AND red_skipped:true
# ALL simultaneously true. Each sub-case flips exactly one condition.
write_gates "light"
assert_transition "claimed->green allow: profile:light + layer:1 + red_skipped:true (all three)" \
  claimed green allow 1 true

write_gates "standard"
assert_transition "claimed->green deny: profile NOT light (standard), layer:1, red_skipped:true" \
  claimed green deny 1 true

write_gates "light"
assert_transition "claimed->green deny: profile:light, layer:0 (not 1), red_skipped:true" \
  claimed green deny 0 true

write_gates "light"
assert_transition "claimed->green deny: profile:light, layer:1, red_skipped:false" \
  claimed green deny 1 false

write_gates "light"
assert_transition "claimed->green deny: profile:light, layer:1, red_skipped missing/empty" \
  claimed green deny 1 ""

write_gates "standard"   # restore default for subsequent cases

# --- Terminal states: withdrawn and superseded have no outbound edges -----
assert_transition "withdrawn->ready deny (terminal state, no outbound edges)" withdrawn ready deny
assert_transition "withdrawn->red deny (terminal state, no outbound edges)" withdrawn red deny
assert_transition "superseded->ready deny (terminal state, no outbound edges)" superseded ready deny
assert_transition "superseded->red deny (terminal state, no outbound edges)" superseded red deny

# --- A transition pair not in the table at all ----------------------------
assert_transition "draft->accepted deny (skips the whole pipeline, not in table)" draft accepted deny

# --- A sample of other disallowed pairs, for contrast ---------------------
assert_transition "red->rejected deny (not in table)" red rejected deny
assert_transition "human_review->red deny (not in table)" human_review red deny
assert_transition "ai_review->accepted deny (not in table, skips human_review)" ai_review accepted deny

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
