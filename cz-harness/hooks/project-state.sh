#!/usr/bin/env bash
# PostToolUse hook (and callable directly by /cz:rebuild-state) — projects
# telemetry/events.jsonl + rd/*.md into state/board.json. Pure function of
# its inputs: deleting board.json and re-running this must reproduce it
# byte-for-byte modulo updated_at (plan §7.1, §13 "board.json drifts" mitigation).
#
# Deliberately NOT where stalls are computed — board.html and /cz:status derive
# "stalled" client-side from state/heartbeats/*.hb vs wall clock. Nothing here
# writes a stall event, by design (plan §7.1, §6.2).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

mkdir -p "$STATE_DIR"
BOARD_FILE="$STATE_DIR/board.json"

PROFILE="$(grep -oE '^profile:[[:space:]]*[a-z]+' "$GATES_YAML" 2>/dev/null | awk '{print $2}')"
PROFILE="${PROFILE:-standard}"

# CZ_PROJECT_CODE is meant to be set by the invoking command/agent runtime,
# but per the "no channel persists an env var into a hook process" note
# above (see cz_sole_lock_file's header comment for the general problem),
# it never actually arrives here in practice — every real run falls through
# to "unknown". Fall back to the one project-level gate record that always
# exists and always names the project: gate-records/PB0-scope.json.
PROJECT_CODE="${CZ_PROJECT_CODE:-}"
if [ -z "$PROJECT_CODE" ] && [ -f "$GATE_RECORDS_DIR/PB0-scope.json" ]; then
  PROJECT_CODE="$(cz_json_field "$GATE_RECORDS_DIR/PB0-scope.json" project)"
fi
PROJECT_CODE="${PROJECT_CODE:-unknown}"
MAX_IN_FLIGHT="$(grep -oE 'max_in_flight:[[:space:]]*[0-9]+' "$GATES_YAML" 2>/dev/null | head -1 | awk '{print $2}')"
MAX_IN_FLIGHT="${MAX_IN_FLIGHT:-3}"

# Plain counters, not an associative array (declare -A needs bash 4+; macOS
# ships bash 3.2 by default, so this must stay bash-3.2-compatible — plan §13).
COUNT_accepted=0; COUNT_in_flight=0; COUNT_in_review=0; COUNT_ready=0
COUNT_blocked_dep=0; COUNT_hard_stop=0; COUNT_stale=0; COUNT_withdrawn=0
COUNT_draft=0; COUNT_superseded=0
# Accumulated as a joined string, not an array — bash 3.2's `set -u` treats a
# reference to a still-empty array ("${arr[@]}") as an unbound variable.
RD_ENTRIES=""
# "<id> <state>\n" lines, looked up by the heartbeat loop below to tell a
# genuinely stuck agent from a stale heartbeat left over from a finished RD.
RD_STATE_LINES=""

if [ -d "$RD_DIR" ]; then
  for rd_file in "$RD_DIR"/*.md; do
    [ -f "$rd_file" ] || continue
    id="$(basename "$rd_file" .md)"
    state="$(cz_rd_field "$rd_file" state)"
    red_skipped="$(cz_rd_field "$rd_file" red_skipped | tr -d ' ')"
    assigned_agent="$(cz_rd_field "$rd_file" assigned_agent | tr -d ' ')"
    claimed_at="$(cz_rd_field "$rd_file" claimed_at | tr -d '"')"
    module="$(cz_rd_field "$rd_file" module | tr -d ' ')"
    summary="$(cz_rd_field "$rd_file" summary | sed -E 's/^"(.*)"$/\1/')"
    leash="$(cz_rd_field "$rd_file" delegation.leash | tr -d ' "')"
    priority="$(cz_rd_field "$rd_file" priority | tr -d ' ')"
    expected_h="$(cz_rd_field "$rd_file" estimate.expected_h | tr -d ' ')"

    # cz_rd_field is a naive scalar reader (no real YAML parsing — see its
    # header comment): a frontmatter value of literal YAML `null` comes back
    # as the 4-character string "null", not empty. Treat that as absent, else
    # it round-trips into board.json as the JSON string "null" instead of the
    # JSON literal null (a real bug: `if (assigned_agent)` truthy-checks on
    # the consuming side would misfire on the non-empty string).
    if [ "$assigned_agent" = "null" ]; then assigned_agent=""; fi
    if [ "$claimed_at" = "null" ]; then claimed_at=""; fi
    if [ "$leash" = "null" ]; then leash=""; fi
    if [ "$priority" = "null" ]; then priority=""; fi
    if [ "$expected_h" = "null" ]; then expected_h=""; fi

    assigned_agent_json="null"
    [ -n "$assigned_agent" ] && assigned_agent_json="\"$assigned_agent\""
    module_json="null"
    [ -n "$module" ] && module_json="\"$(cz_json_escape "$module")\""
    summary_json="null"
    [ -n "$summary" ] && summary_json="\"$(cz_json_escape "$summary")\""
    leash_json="null"
    [ -n "$leash" ] && leash_json="\"$leash\""

    # priority (board feature, 2026-08-04): optional field (docs/TRACEABILITY.md
    # already names it as content_hash-excluded operational metadata, but it was
    # never actually added to rd.schema.json/rd-template.yaml until now) — an RD
    # authored before this feature, or one whose author simply omitted it, has no
    # `priority:` line at all. Default to "medium" rather than surfacing null, so
    # the board's priority filter/column has something meaningful to show for
    # every RD without requiring a backfill of existing rd/*.md files.
    priority_json="\"${priority:-medium}\""

    # complexity: display-only bucket derived from the existing three-point
    # estimate (estimate.expected_h, already bounded 0-4h by rd.schema.json) —
    # not a stored field, so there's nothing to backfill. Thresholds chosen to
    # split that 0-4h range into three roughly even bands.
    complexity_json="null"
    if [ -n "$expected_h" ]; then
      complexity="$(awk -v h="$expected_h" 'BEGIN {
        if (h <= 1.5) print "low";
        else if (h <= 3) print "medium";
        else print "high";
      }')"
      [ -n "$complexity" ] && complexity_json="\"$complexity\""
    fi

    # cost_usd (audit finding C8): rolled up by summing the "cost_usd" field
    # across every telemetry/events.jsonl line tagged with this RD's id —
    # events.jsonl (not the RD file) is the only place a per-call dollar
    # figure could ever be recorded (see emit-telemetry.sh's CZ_LAST_COST_USD
    # extension point). Distinguish "no cost-bearing event exists yet for
    # this RD" (null — honestly means "no data", matches board-state schema's
    # ["number","null"] type) from "cost-bearing events exist and sum to
    # zero" (0) — collapsing those two into the same 0 would silently claim
    # data that doesn't exist. Plain grep/awk, no jq dependency, same
    # tradeoff as cz_rd_field/cz_json_field elsewhere in this codebase.
    cost_usd_json="null"
    if [ -f "$TELEMETRY_FILE" ]; then
      cost_matches="$(grep -F "\"rd\":\"$id\"" "$TELEMETRY_FILE" 2>/dev/null \
        | grep -oE '"cost_usd"[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?' \
        | grep -oE '[0-9]+(\.[0-9]+)?$' || true)"
      if [ -n "$cost_matches" ]; then
        cost_usd_json="$(printf '%s\n' "$cost_matches" | awk '{sum+=$1} END{printf "%.4f", sum}')"
      fi
    fi

    # "time in state" should measure dwell in the RD's CURRENT state, not
    # time-since-first-claim — using claimed_at unconditionally overstates
    # dwell for `accepted` RDs by the whole build/review duration that
    # preceded acceptance. Prefer the gate record's own decision timestamp
    # (the actual moment the RD entered `accepted`) when one exists.
    state_anchor="$claimed_at"
    gate_ts=""
    if [ "$state" = "accepted" ]; then
      gate_record="$GATE_RECORDS_DIR/${id}-gate.json"
      if [ -f "$gate_record" ]; then
        gate_ts="$(cz_json_field "$gate_record" timestamp)"
        if [ -n "$gate_ts" ]; then state_anchor="$gate_ts"; fi
      fi
    fi

    # finished_date (board feature, 2026-08-04): reuses the same gate-record
    # timestamp already read above for state_anchor — the actual moment this
    # RD's gate_decision was approved. null for any RD not yet accepted, or an
    # accepted RD with no gate record on disk (shouldn't happen in practice,
    # but the field must stay honestly null rather than fabricate a date).
    finished_date_json="null"
    [ "$state" = "accepted" ] && [ -n "$gate_ts" ] && finished_date_json="\"$gate_ts\""

    time_in_state_s="null"
    claimed_epoch="$(cz_iso_to_epoch "$state_anchor")"
    if [ -n "$claimed_epoch" ]; then
      time_in_state_s=$(( $(date -u +%s) - claimed_epoch ))
    fi

    case "$state" in
      accepted) COUNT_accepted=$((COUNT_accepted+1)) ;;
      claimed|red|green) COUNT_in_flight=$((COUNT_in_flight+1)) ;;
      ai_review|sec_review|human_review) COUNT_in_review=$((COUNT_in_review+1)) ;;
      ready) COUNT_ready=$((COUNT_ready+1)) ;;
      blocked_dep) COUNT_blocked_dep=$((COUNT_blocked_dep+1)) ;;
      blocked_hardstop) COUNT_hard_stop=$((COUNT_hard_stop+1)) ;;
      stale) COUNT_stale=$((COUNT_stale+1)) ;;
      withdrawn) COUNT_withdrawn=$((COUNT_withdrawn+1)) ;;
      draft) COUNT_draft=$((COUNT_draft+1)) ;;
      superseded) COUNT_superseded=$((COUNT_superseded+1)) ;;
    esac

    entry="{\"id\":\"$id\",\"state\":\"$state\",\"module\":$module_json,\"summary\":$summary_json,\"assigned_agent\":$assigned_agent_json,\"time_in_state_s\":$time_in_state_s,\"red_skipped\":${red_skipped:-false},\"leash\":$leash_json,\"cost_usd\":$cost_usd_json,\"priority\":$priority_json,\"complexity\":$complexity_json,\"finished_date\":$finished_date_json}"
    RD_ENTRIES="${RD_ENTRIES:+$RD_ENTRIES,}$entry"

    # Recorded so the heartbeat loop below can tell "this RD is still
    # in-flight" from "this RD is done" — see the false-stall note there.
    RD_STATE_LINES="${RD_STATE_LINES}${id} ${state}
"
  done
fi

TOTAL=$((COUNT_accepted + COUNT_in_flight + COUNT_in_review + COUNT_ready + COUNT_blocked_dep + COUNT_hard_stop + COUNT_stale + COUNT_withdrawn + COUNT_draft + COUNT_superseded))

# agent_state/rd distinguish "actively working RD-X" from "no assigned RD"
# (schema requires agent_state — board.html/cz:status pair this with
# last_heartbeat age to derive "stalled" client-side; see emit-telemetry.sh).
AGENT_ENTRIES=""
if [ -d "$STATE_DIR/heartbeats" ]; then
  for hb in "$STATE_DIR/heartbeats"/*.hb; do
    [ -f "$hb" ] || continue
    agent="$(basename "$hb" .hb)"
    raw="$(cat "$hb")"
    case "$raw" in
      \{*)
        ts="$(cz_json_field "$hb" last_heartbeat)"
        agent_state="$(cz_json_field "$hb" agent_state)"
        rd="$(cz_json_field "$hb" rd)"
        ;;
      *)
        # Legacy plain-timestamp heartbeat (pre phase-1.0.1 hooks) — degrade gracefully.
        ts="$raw"; agent_state="executing"; rd=""
        ;;
    esac
    agent_state="${agent_state:-executing}"

    # False-stall guard: a heartbeat file is written while an agent works an
    # RD and (by design, per this file's header comment) nothing guarantees
    # it gets cleared once that RD finishes — release-lock.sh best-effort
    # deletes it on rd_release, but any path that misses that (a crash, a
    # manual edit, a future code path) leaves it frozen at agent_state
    # "executing" forever. Since board.html/cz:status derive "stalled" purely
    # from agent_state=="executing" + heartbeat age (schema comment on
    # `agents`), a stale file falsely and permanently reports a stall for an
    # RD that is actually done. Cross-check against this run's freshly-read
    # RD states (the source of truth) and downgrade to "idle" whenever the
    # referenced RD has already reached a terminal state — self-healing on
    # every board rebuild regardless of whether the heartbeat file itself
    # was ever cleaned up.
    if [ -n "$rd" ] && [ "$rd" != "null" ] && [ "$agent_state" = "executing" ]; then
      rd_state="$(printf '%s' "$RD_STATE_LINES" | awk -v id="$rd" '$1==id{print $2; exit}')"
      case "$rd_state" in
        accepted|superseded|withdrawn) agent_state="idle" ;;
      esac
    fi

    rd_json="null"
    [ -n "$rd" ] && [ "$rd" != "null" ] && rd_json="\"$rd\""
    entry="{\"agent\":\"$agent\",\"agent_state\":\"$agent_state\",\"rd\":$rd_json,\"last_heartbeat\":\"$ts\"}"
    AGENT_ENTRIES="${AGENT_ENTRIES:+$AGENT_ENTRIES,}$entry"
  done
fi

# Phase pipeline (project-level phases only — 7/8/9 are per-RD, shown in the
# RD board above instead of here). Sourced from gate-records/PB<n>-*.json.
PHASE_ENTRIES=""
for step in 0 1 2 3 4 5 6 10; do
  case "$step" in
    0) name="Scope" ;; 1) name="Spec" ;; 2) name="Modulemap" ;; 3) name="Arch" ;;
    4) name="WBS" ;; 5) name="Estimate" ;; 6) name="Risk" ;; 10) name="Report" ;;
  esac
  status="not_started"
  artifact="null"
  gate_file="$(ls "$GATE_RECORDS_DIR"/PB${step}-*.json 2>/dev/null | head -1)" || true
  if [ -n "$gate_file" ]; then
    status="$(cz_json_field "$gate_file" status)"
    status="${status:-not_started}"
    artifact_name="$(cz_json_field "$gate_file" artifact)"
    if [ -n "$artifact_name" ]; then
      artifact="\"$artifact_name\""
    else
      # Some gate records (e.g. PB6-risk.json) name their output(s) under a
      # plural "artifacts" array instead of a singular "artifact" string —
      # cz_json_field only reads flat scalars, so that array was silently
      # read as absent, leaving a real artifact's phase entry as null.
      artifacts_list="$(tr -d '\n' < "$gate_file" 2>/dev/null \
        | grep -oE '"artifacts"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
        | grep -oE '"[^"]*"' | tail -n +2 | paste -sd, -)"
      if [ -n "$artifacts_list" ]; then artifact="[$artifacts_list]"; fi
    fi
  fi
  entry="{\"step\":$step,\"name\":\"$name\",\"status\":\"$status\",\"artifact\":$artifact}"
  PHASE_ENTRIES="${PHASE_ENTRIES:+$PHASE_ENTRIES,}$entry"
done

cat > "$BOARD_FILE" <<EOF
{
  "project": "$PROJECT_CODE",
  "profile": "$PROFILE",
  "updated_at": "$(cz_now)",
  "concurrency": { "max_in_flight": $MAX_IN_FLIGHT },
  "counts": {
    "accepted": $COUNT_accepted, "in_flight": $COUNT_in_flight, "in_review": $COUNT_in_review,
    "ready": $COUNT_ready, "blocked_dep": $COUNT_blocked_dep, "hard_stop": $COUNT_hard_stop,
    "stale": $COUNT_stale, "withdrawn": $COUNT_withdrawn, "draft": $COUNT_draft,
    "superseded": $COUNT_superseded, "total": $TOTAL
  },
  "rds": [$RD_ENTRIES],
  "agents": [$AGENT_ENTRIES],
  "phases": [$PHASE_ENTRIES]
}
EOF

cz_log "state/board.json rebuilt: $TOTAL RDs, profile=$PROFILE"
