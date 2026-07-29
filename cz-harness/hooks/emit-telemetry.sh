#!/usr/bin/env bash
# PostToolUse hook — fires after EVERY tool call, test run, gate decision, and
# approval. Appends one event to telemetry/events.jsonl (append-only, immutable)
# and writes a heartbeat for the acting agent. This is what makes stall
# detection and the live board possible without any agent self-reporting status
# (plan §7.1, §10).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

HOOK_INPUT="$(cat)"
TOOL_NAME="$(echo "$HOOK_INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"(.*)"/\1/' || echo "unknown")"

# CZ_ACTING_AGENT/CZ_ACTIVE_RD are almost never actually set (no command or
# agent definition exports them, and env vars can't survive across separate
# Bash tool calls or into a Task-dispatched subagent anyway) — fall back to
# disk. First try to pull an RD id out of this specific tool call (file path,
# Bash command, etc. — the whole HOOK_INPUT blob), then look up THAT RD's own
# lock; this disambiguates correctly even with several RDs claimed at once.
# Only if the call carries no RD id anywhere does this fall back to the
# sole-active-lock guess. See lib/common.sh's "Identity fallback" section.
AGENT="${CZ_ACTING_AGENT:-}"
RD_ID="${CZ_ACTIVE_RD:-}"
[ -n "$RD_ID" ] || RD_ID="$(cz_extract_rd_id "$HOOK_INPUT")"
if [ -n "$RD_ID" ]; then
  [ -n "$AGENT" ] || AGENT="$(cz_lock_agent_for_rd "$RD_ID")"
  # RD id resolved (e.g. found in the tool call's own text) but no lock is
  # currently held for it — not uncommon (a stale reference, a review pass
  # touching an already-accepted RD, ...). Last resort before "unknown": the
  # RD record itself names who it's assigned to (rd/*.md's assigned_agent
  # frontmatter field, the same field project-state.sh already reads).
  if [ -z "$AGENT" ]; then
    RD_FILE_FOR_LOOKUP="$(cz_rd_path "$RD_ID")"
    if [ -f "$RD_FILE_FOR_LOOKUP" ]; then
      AGENT="$(cz_rd_field "$RD_FILE_FOR_LOOKUP" assigned_agent | tr -d ' "')"
      [ "$AGENT" != "null" ] || AGENT=""
    fi
  fi
else
  [ -n "$AGENT" ] || AGENT="$(cz_sole_lock_agent)"
  RD_ID="$(cz_sole_lock_rd)"
fi
# Remember whether identity actually resolved (non-empty AGENT) BEFORE the
# "unknown" fallback below — a bare tool call that carries no RD id, fired
# while >1 RD is claimed, is genuinely ambiguous (cz_sole_lock_agent only
# disambiguates the single-lock case). Writing such a call's heartbeat into a
# shared unknown.hb would masquerade as a 4th "agent" card on the board even
# though it's really just noise from one of the real N agents. The telemetry
# event itself still gets recorded (append-only audit trail, plan §7.1) — only
# the heartbeat write (which drives the agents[] board panel) is skipped.
#
# "unknown" (agent) and JSON null (rd, built below) are BOTH schema-legal,
# deliberate values (telemetry-event.schema.json's agent enum includes
# "unknown", and rd's type is ["string","null"]) — not a bug being papered
# over. A huge share of real agent_dispatch events genuinely have neither: all
# of phases 0-6/10 (ba/sa/planner/risk-gov/agentops never hold an rd/*.md
# claim lock, since those phases aren't per-RD) fire this hook with no RD in
# scope at all, and no command at those phases ever sets CZ_ACTING_AGENT
# either (grep commands/*.md — only cz-build.md/cz-run.md do). Forcing a fake
# RD-shaped string or a fake agent name into those events to satisfy a
# stricter schema would be actively dishonest telemetry; audit finding C7 was
# about literal, unmarked schema *violations* (an enum value and a pattern
# both silently broken), not about this fallback existing at all.
IDENTITY_RESOLVED=1
[ -n "$AGENT" ] || IDENTITY_RESOLVED=0
AGENT="${AGENT:-unknown}"
RD_ID="${RD_ID:-null}"
RUN_ID="${CZ_RUN_ID:-r-$(date +%s)}"

RD_JSON="null"
[ "$RD_ID" != "null" ] && RD_JSON="\"$RD_ID\""

# cost_usd/cost_source: this hook fires on a tool-call boundary (PostToolUse),
# which carries no token/cost accounting from Claude Code itself — there is no
# real source for these here, full stop (plan §10's "cost_source: gateway"
# case applies once an actual billing/gateway response exists, not to a bare
# tool call). Rather than hand-wave this into the same "unknown"/null story as
# rd/agent above, this hook exposes a genuine, opt-in extension point: if
# something upstream (a future gateway-aware wrapper) already knows the cost
# of the work that just happened, it can pass it in via CZ_LAST_COST_USD (and
# optionally CZ_LAST_COST_SOURCE) and this hook will thread it into the event.
# Nothing in this plugin sets these env vars yet — cost_usd stays null on
# every real event today, and hooks/project-state.sh's cost_usd rollup (C8)
# correctly sums to 0 until a real producer exists. That is an honest zero,
# not a silent schema gap.
COST_JSON=""
if [ -n "${CZ_LAST_COST_USD:-}" ]; then
  COST_SOURCE="${CZ_LAST_COST_SOURCE:-gateway}"
  COST_JSON=",\"cost_usd\":${CZ_LAST_COST_USD},\"cost_source\":\"$COST_SOURCE\""
fi

# Heartbeat file — read by board.html / /cz:status / project-state.sh to derive
# "stalled" and "which RD is this agent on" (schema requires agent_state + rd
# on every agents[] entry). No stall event is ever written to the log itself —
# stalls are computed client-side from last_heartbeat age (plan §7.1, §6.2).
if [ "$IDENTITY_RESOLVED" -eq 1 ]; then
  mkdir -p "$STATE_DIR/heartbeats"
  HB_FILE="$STATE_DIR/heartbeats/$AGENT.hb"

  # state/heartbeats/*.hb and state/locks/*.lock are overwritten in place by
  # design (board.html/project-state.sh want "current state", not history) —
  # but that means the prior value is gone forever once overwritten, so no
  # historical stall/handoff can ever be audited after the fact. Emit a
  # durable telemetry event on every REAL transition (this agent moved onto a
  # different RD, or this is its first heartbeat) before overwriting the
  # file. Only a tick with the same rd is a no-op refresh — logging every tick
  # would flood the log worse than agent_dispatch already does, so this must
  # diff old vs new before deciding to emit.
  #
  # Event name is "agent_heartbeat" — the schema's existing enum value for
  # this concept (audit finding C7: this hook used to emit an unlisted
  # "heartbeat_transition" name instead of the schema's real one). Nothing
  # else in the plugin emits "agent_heartbeat", so this is the sole, correct
  # producer, not a duplicate of some other event.
  PREV_RD="null"
  if [ -f "$HB_FILE" ]; then
    PREV_RD="$(cz_json_field "$HB_FILE" rd)"
    PREV_RD="${PREV_RD:-null}"
  fi
  if [ "$PREV_RD" != "$RD_ID" ]; then
    cz_emit_event "{\"ts\":\"$(cz_now)\",\"run_id\":\"$RUN_ID\",\"rd\":$RD_JSON,\"agent\":\"$AGENT\",\"event\":\"agent_heartbeat\",\"result\":\"from_$PREV_RD\"$COST_JSON}"
  fi

  cat > "$HB_FILE" <<EOF
{"last_heartbeat":"$(cz_now)","agent_state":"executing","rd":$RD_JSON}
EOF
else
  cz_log "identity unresolved (no RD id in call, >1 lock held) — skipping heartbeat write to avoid a phantom 'unknown' agent card"
fi

EVENT_LINE=$(cat <<EOF
{"ts":"$(cz_now)","run_id":"$RUN_ID","rd":$RD_JSON,"agent":"$AGENT","event":"agent_dispatch","tool_name":"$TOOL_NAME","result":"ok"$COST_JSON}
EOF
)
cz_emit_event "$EVENT_LINE"

exit 0
