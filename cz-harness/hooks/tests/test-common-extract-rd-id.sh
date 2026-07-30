#!/usr/bin/env bash
# Self-test for hooks/lib/common.sh's cz_extract_rd_id.
#
# Live incident: RD-AIBOOTCAMP-009.01c's build process died without releasing
# its claim lock. A completely unrelated Claude Code session, merely
# inspecting the stale state (`cat state/locks/RD-...c.lock`, `grep ...
# telemetry/events.jsonl`), had cz_extract_rd_id pull that RD's id straight
# out of its own diagnostic command text. emit-telemetry.sh then resolved
# identity via cz_lock_agent_for_rd and kept overwriting the dead build's
# heartbeat, making it look perpetually alive and masking the real stall for
# 15+ minutes. Fixed: cz_extract_rd_id now strips state/locks/*, state/
# heartbeats/*, state/board.json, and telemetry/* references before matching
# — those paths are diagnostic/introspective ABOUT an RD, never work ON one.
# Genuine artifact paths (evidence/, deliverables/, rd/, tests/, src/, ...)
# are unaffected.
#
# Pure function test — no CZ_ROOT/filesystem fixture needed beyond what
# sourcing common.sh itself requires (a scratch CZ_ROOT so its startup guard
# doesn't fail loudly per audit finding C5's fix).
#
# Usage: bash hooks/tests/test-common-extract-rd-id.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export CZ_ROOT
CZ_ROOT="$(mktemp -d)"
trap 'rm -rf "$CZ_ROOT"' EXIT
mkdir -p "$CZ_ROOT/rd" "$CZ_ROOT/state/locks" "$CZ_ROOT/state/heartbeats" \
         "$CZ_ROOT/telemetry" "$CZ_ROOT/gate-records" "$CZ_ROOT/config"

set +u  # common.sh assumes an interactive-ish env for some checks; matches other tests' style
source "$DIR/../lib/common.sh"
set -u

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

R="$(cz_extract_rd_id 'cat state/locks/RD-AIBOOTCAMP-009.01c.lock')"
check "state/locks/*.lock reference does not resolve an RD id" "$([ -z "$R" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'cat state/heartbeats/RD-AIBOOTCAMP-005.01c.hb')"
check "state/heartbeats/*.hb reference does not resolve an RD id" "$([ -z "$R" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'grep "009.01c" telemetry/events.jsonl')"
check "telemetry/events.jsonl reference does not resolve an RD id" "$([ -z "$R" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'evidence/RD-AIBOOTCAMP-009.01c/red.log')"
check "a genuine evidence/ artifact path still resolves its RD id" "$([ "$R" = "RD-AIBOOTCAMP-009.01c" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'deliverables/DEVBOOK-RD-AIBOOTCAMP-005.01a.md')"
check "a genuine deliverables/ artifact path still resolves its RD id" "$([ "$R" = "RD-AIBOOTCAMP-005.01a" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'gate-records/RD-AIBOOTCAMP-005.01c-gate.json')"
check "a genuine gate-records/ artifact path still resolves its RD id" "$([ "$R" = "RD-AIBOOTCAMP-005.01c" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'cat state/locks/RD-AIBOOTCAMP-009.01c.lock && cat evidence/RD-AIBOOTCAMP-005.01a/red.log')"
check "mixed noise + genuine reference resolves the genuine one, not the noise one" "$([ "$R" = "RD-AIBOOTCAMP-005.01a" ] && echo 1 || echo 0)"

R="$(cz_extract_rd_id 'no RD reference anywhere in this string')"
check "no reference at all resolves to empty" "$([ -z "$R" ] && echo 1 || echo 0)"

echo "---"
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
