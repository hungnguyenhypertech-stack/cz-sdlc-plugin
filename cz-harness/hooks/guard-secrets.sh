#!/usr/bin/env bash
# PreToolUse hook — deny-list enforcement. Blocks any write that introduces a
# hardcoded credential pattern, and any write into a hazard path bypassing the
# gate profile (defence in depth alongside detect-hazard.sh).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
CONTENT="$(echo "$HOOK_INPUT" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"

DENY_PATTERNS=(
  'AKIA[0-9A-Z]{16}'                     # AWS access key
  '-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----'
  '(api|secret)[_-]?key["'\'']?\s*[:=]\s*["'\'']?[A-Za-z0-9/+]{16,}'
  'password["'\'']?\s*[:=]\s*["'\'']?[^"'\'' ]{6,}'
  'sk-[A-Za-z0-9]{20,}'                  # OpenAI/Anthropic-style secret key
  'ghp_[A-Za-z0-9]{30,}'                 # GitHub PAT
)

for pat in "${DENY_PATTERNS[@]}"; do
  if printf '%s\n' "$CONTENT" | grep -qEi -e "$pat"; then
    cz_deny "content matches secrets deny-list pattern ($pat) — no hardcoded credentials, use env/secret manager references instead"
  fi
done

exit 0
