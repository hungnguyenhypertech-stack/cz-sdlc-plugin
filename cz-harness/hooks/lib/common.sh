#!/usr/bin/env bash
# Shared helpers for cz-harness hooks. Sourced, never executed directly.
set -euo pipefail

# CLAUDE_PROJECT_DIR (set by Claude Code for hook processes) is the project
# root regardless of the invoking shell's cwd. $(pwd) used to be a
# last-resort fallback here — that is exactly what caused a real incident
# (audit finding C5): an agent's earlier `cd` into a subdirectory persisted
# for the rest of that session, so a later PostToolUse hook ran with
# CZ_ROOT=<that subdirectory> and wrote a stray state/telemetry/rd tree
# there instead of the project root — and it kept happening silently because
# nothing ever failed loudly. A hook running with the wrong root is worse
# than a hook that refuses to run at all, so this no longer falls back to
# $(pwd): if neither CZ_ROOT nor CLAUDE_PROJECT_DIR is set, fail loudly
# instead of guessing. Tests/manual invocations should export CZ_ROOT
# explicitly (every hooks/tests/test-*.sh script in this plugin does).
if [ -n "${CZ_ROOT:-}" ]; then
  : # explicit override — trusted as-is (used by this plugin's own tests)
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  CZ_ROOT="$CLAUDE_PROJECT_DIR"
else
  echo "[cz-harness] FATAL: neither CZ_ROOT nor CLAUDE_PROJECT_DIR is set." >&2
  echo "[cz-harness] Refusing to fall back to \$(pwd) — that previously caused a real incident where hooks silently wrote state/telemetry/rd into whatever subdirectory a stale 'cd' had left the shell in (audit finding C5)." >&2
  echo "[cz-harness] Set CLAUDE_PROJECT_DIR (Claude Code sets this automatically for hook processes) or export CZ_ROOT explicitly before invoking this hook." >&2
  exit 1
fi
RD_DIR="$CZ_ROOT/rd"
STATE_DIR="$CZ_ROOT/state"
LOCK_DIR="$STATE_DIR/locks"
EVIDENCE_DIR="$CZ_ROOT/evidence"
GATE_RECORDS_DIR="$CZ_ROOT/gate-records"
TELEMETRY_FILE="$CZ_ROOT/telemetry/events.jsonl"
GATES_YAML="$CZ_ROOT/config/gates.yaml"
# Every agent's narrative/report output (SCOPE, SPEC, ARCH, RISK, reviews,
# RTM, WEEKLY, CASE-STUDY, ...) lives here, each with an auto-rendered HTML
# sibling — see docs/DELIVERABLES.md. Machine state (rd/*.md, state/**,
# telemetry/**, gate-records/**) is NOT part of this tree; it's schema'd data
# already, not a human-review document.
DELIVERABLES_DIR="$CZ_ROOT/deliverables"

cz_log() { echo "[cz-harness] $*" >&2; }
cz_deny() { echo "[cz-harness] DENIED: $*" >&2; exit 1; }

# cz_python: prints the path of a python3 interpreter that actually RUNS, or ""
# if none is available. Callers must test for empty and degrade gracefully.
#
# `command -v python3` is NOT sufficient on Windows: it ships an App Execution
# Alias stub at .../WindowsApps/python3.exe that exists, is executable, and
# always fails with "Python was not found; run without arguments to install
# from the Microsoft Store". Every caller here guarded on `command -v python3`,
# passed that guard, then silently failed — which is why deliverable HTML
# rendering, deliverables/index.json, and the audit index all quietly produced
# nothing on Windows while every hook still reported success.
#
# So: probe candidates by actually executing one, and accept `python` (the name
# a real Windows install uses) as well as `python3`. Result is memoized in
# CZ_PYTHON for the life of the process.
cz_python() {
  if [ -n "${CZ_PYTHON:-}" ]; then
    printf '%s' "$CZ_PYTHON"
    return 0
  fi
  local c
  for c in "${CZ_PYTHON_BIN:-}" python3 python py; do
    [ -n "$c" ] || continue
    command -v "$c" >/dev/null 2>&1 || continue
    if "$c" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
      CZ_PYTHON="$(command -v "$c")"
      export CZ_PYTHON
      printf '%s' "$CZ_PYTHON"
      return 0
    fi
  done
  return 0
}

# cz_now: RFC3339 UTC timestamp
cz_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# cz_emit_event <json-line>
# Appends one line to telemetry/events.jsonl. This is the ONLY writer of truth
# (plan §7.1) — hooks call this, agents never write telemetry directly.
cz_emit_event() {
  local line="$1"
  mkdir -p "$(dirname "$TELEMETRY_FILE")"
  echo "$line" >> "$TELEMETRY_FILE"
}

# cz_rd_fm <rd-file-path>: prints the YAML frontmatter body (the lines
# between the first and second "---" delimiters), or the whole file if it has
# no frontmatter delimiters at all (kept for backward-compat with any bare
# rd/*.yaml file that isn't a Markdown+frontmatter RD).
cz_rd_fm() {
  local file="$1"
  if grep -qE '^---[ \t]*$' "$file" 2>/dev/null; then
    awk '/^---[ \t]*$/{c++; next} c==1' "$file"
  else
    cat "$file"
  fi
}

# cz_rd_field <rd-file-path> <field>
# Minimal YAML scalar reader over an RD's frontmatter. <field> may be a
# top-level key ("state", "content_hash", ...) or one level of nesting via
# dot notation ("evidence.red_log", "delegation.level", "estimate.expected_h")
# — RD records nest a handful of fields one level deep (delegation/estimate/
# evidence blocks). Real implementation should shell out to yq; this is a
# dependency-free fallback, deliberately not a general YAML parser.
cz_rd_field() {
  local file="$1" field="$2" parent child
  if [[ "$field" == *.* ]]; then
    parent="${field%%.*}"
    child="${field#*.}"
    cz_rd_fm "$file" | awk -v p="$parent" -v c="$child" '
      $0 ~ "^"p":" { inblock=1; next }
      inblock && $0 ~ "^[^ \t]" { inblock=0 }
      inblock && $0 ~ "^[ \t]+"c":" {
        v=$0; sub("^[ \t]+"c":[ \t]*", "", v); print v; exit
      }'
  else
    cz_rd_fm "$file" | awk -v f="$field" '
      $0 ~ "^"f":" { v=$0; sub("^"f":[ \t]*", "", v); print v; exit }'
  fi
}

# cz_rd_tests_list <rd-file-path>: prints one TC id per line from the RD's
# `tests:` field. Supports both the multi-line indented-list form the shipped
# rd-template.yaml actually uses:
#   tests:
#     - TC-PB0X-012.03-1
#     - TC-PB0X-012.03-2
# ...and the single-line bracketed form from the plan's raw §4.2 example:
#   tests: [TC-PB04-012.03-1, TC-PB04-012.03-2]
# Prints nothing if the RD has no tests: field or an empty list.
cz_rd_tests_list() {
  local file="$1"
  cz_rd_fm "$file" | awk '
    /^tests:[[:space:]]*\[/ {
      line=$0
      sub(/^tests:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, arr, ",")
      for (i=1; i<=n; i++) {
        v = arr[i]
        gsub(/^[[:space:]]+/, "", v); gsub(/[[:space:]]+$/, "", v)
        if (v != "") print v
      }
      next
    }
    /^tests:[[:space:]]*$/ { inblock=1; next }
    inblock && /^[^ \t]/ { inblock=0 }
    inblock && /^[ \t]*-/ {
      v=$0
      sub(/^[ \t]*-[ \t]*/, "", v)
      gsub(/^[[:space:]]+/, "", v); gsub(/[[:space:]]+$/, "", v)
      if (v != "") print v
    }
  '
}

# cz_json_escape <string>: escapes backslashes and double-quotes so <string>
# is safe to interpolate into a hand-built JSON string value (this codebase
# has no jq dependency — see cz_rd_field's header comment for the same
# tradeoff). Strips any embedded newline/CR since every field built this way
# (module, summary, ...) is expected to be a single YAML scalar line already.
cz_json_escape() {
  printf '%s' "$1" | tr -d '\n\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# cz_json_unescape <json-string-body>: inverse of cz_json_escape, generalized
# to also decode \n/\t/\r (cz_json_escape never produces these since it
# strips real newlines/CRs first, but a JSON string value read off the wire —
# e.g. a hook's "content" field carrying a multi-line file's content — uses
# these escapes routinely, so the decoder must handle them even though the
# encoder here doesn't emit them). <json-string-body> is the value BETWEEN
# the surrounding quotes (i.e. already stripped of the outer `"..."`), as
# extracted by a caller's own grep/sed against raw hook-input JSON — this
# function does no JSON structural parsing of its own, consistent with every
# other JSON helper in this file (cz_json_field, cz_rd_field) being a
# dependency-free best-effort reader, not a general parser.
#
# Byte-exact: writes to stdout via printf, never through a `$(...)` capture,
# so a trailing real newline in the decoded content survives. A caller that
# captures this into a shell variable via command substitution will still
# lose a trailing newline (bash strips it) — redirect to a file instead when
# exact trailing bytes matter (see guard-role-boundaries.sh's telemetry
# append-only check, which does exactly this).
cz_json_unescape() {
  local s="$1"
  printf '%s' "$s" | awk '
  {
    line = $0
    out = ""
    n = length(line)
    i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (c == "\\" && i < n) {
        nc = substr(line, i+1, 1)
        if (nc == "n")       { out = out "\n"; i += 2 }
        else if (nc == "t")  { out = out "\t"; i += 2 }
        else if (nc == "r")  { out = out "\r"; i += 2 }
        else if (nc == "\"") { out = out "\""; i += 2 }
        else if (nc == "\\") { out = out "\\"; i += 2 }
        else if (nc == "/")  { out = out "/";  i += 2 }
        else                 { out = out c nc; i += 2 }
      } else {
        out = out c; i += 1
      }
    }
    printf "%s", out
  }'
}

# cz_content_hash <statement> <ac-json> <nfr-json>
# content_hash covers ONLY statement + ac[] + nfr_refs (plan §4.2) — never
# estimate, assigned_agent, state, etc. Editing those must NOT invalidate tests.
cz_content_hash() {
  printf '%s' "$1$2$3" | sha256sum | awk '{print "sha256:"$1}'
}

# cz_rd_path <rd-id>: RDs are Markdown files with a YAML frontmatter block
# (rd/<id>.md), not bare rd/<id>.yaml — see docs/RD-GUIDE.md and cz-rd.md's
# "content_hash computed" write target.
cz_rd_path() { echo "$RD_DIR/$1.md"; }

# cz_known_rd_ids: prints one real RD id per line (rd/<id>.md basenames,
# .md stripped), or nothing if $RD_DIR doesn't exist. telemetry/events.jsonl
# accumulates event lines referencing RD ids that were never committed as a
# real rd/*.md file (test fixtures, ad-hoc manual runs, self-referential
# tool-call noise from an /cz:audit session touching the project itself) —
# any consumer folding telemetry into a projection (/cz:rebuild-state,
# /cz:audit) should filter against this list first, so that noise doesn't
# get treated as a real RD's lifecycle event.
cz_known_rd_ids() {
  local f
  if [ -d "$RD_DIR" ]; then
    for f in "$RD_DIR"/*.md; do
      [ -f "$f" ] || continue
      basename "$f" .md
    done
  fi
  return 0
}

# cz_is_hazard <rd-id>: true if rd/<id>.md's frontmatter has hazard: true
cz_is_hazard() {
  local path
  path="$(cz_rd_path "$1")"
  [ -f "$path" ] && cz_rd_fm "$path" | grep -qE '^hazard:[[:space:]]*true'
}

# --- Identity fallback -------------------------------------------------
# CZ_ACTING_AGENT / CZ_ACTIVE_RD are meant to be set by the invoking
# command/agent runtime, but there is no channel that actually propagates an
# env var into a hook process: Claude Code's Bash tool does not persist shell
# state between tool calls, and a Task-dispatched subagent runs its own tool
# loop with no shared shell at all. Env vars therefore only ever work for a
# single inline invocation (e.g. `CZ_ACTING_AGENT=x ./guard-claim-lock.sh`).
# For every other hook firing (which is most of them — PostToolUse fires on
# every tool call for the lifetime of a claim), the only thing that actually
# persists across process boundaries is the filesystem. state/locks/*.lock
# already records "which agent claimed which RD" at claim time (see
# guard-claim-lock.sh) — so when the env var isn't set, fall back to reading
# that lock, disambiguating by which single RD is unambiguous:
#   - exactly one lock held -> that lock's agent/RD is almost certainly who's
#     acting (single-claim is the common case; sub-pm enforces max_in_flight
#     but concurrent claims are still possible under standard/heavy profiles)
#   - zero or >1 locks held -> ambiguous, caller must use its own default
#     ("unknown" for telemetry, "human" for role-boundary checks)
#
# cz_sole_lock_file: prints the path of the only active lock, or "" if zero
# or more than one lock file exists. Plain-string accumulation, not an array
# — same bash-3.2 "${arr[@]} is unbound under set -u when empty" pitfall
# noted elsewhere in this file.
# NOTE: every function below always returns 0. Under `set -euo pipefail` in
# the sourcing hook, a helper returning non-zero from a plain `x="$(fn)"`
# assignment (not inside an if/while/&&/||) would abort the whole hook — these
# are best-effort lookups, never a reason to fail the caller.
cz_sole_lock_file() {
  local f found="" count=0
  if [ -d "$LOCK_DIR" ]; then
    for f in "$LOCK_DIR"/*.lock; do
      [ -f "$f" ] || continue
      count=$((count+1))
      found="$f"
    done
  fi
  [ "$count" -eq 1 ] && echo "$found"
  return 0
}

# cz_sole_lock_agent: prints the agent of the only active lock, or "" if
# zero or more than one lock file exists.
cz_sole_lock_agent() {
  local f
  f="$(cz_sole_lock_file)"
  [ -n "$f" ] && awk -F= '/^agent=/{print $2}' "$f"
  return 0
}

# cz_sole_lock_rd: prints the RD id of the only active lock, or "" if zero
# or more than one lock file exists.
cz_sole_lock_rd() {
  local f
  f="$(cz_sole_lock_file)"
  [ -n "$f" ] && basename "$f" .lock
  return 0
}

# cz_locked_rd_ids: prints one currently-claimed RD id per line (state/locks/
# *.lock basenames), or nothing if no lock is held. Unlike cz_sole_lock_rd this
# does not collapse to "" when several claims exist — a caller that has its own
# candidate RD (e.g. an id parsed out of an incoming write's content) can
# intersect against this set to disambiguate under bounded/wave concurrency,
# where sole-lock resolution is unavailable by construction.
cz_locked_rd_ids() {
  local f
  if [ -d "$LOCK_DIR" ]; then
    for f in "$LOCK_DIR"/*.lock; do
      [ -f "$f" ] || continue
      basename "$f" .lock
    done
  fi
  return 0
}

# cz_lock_agent_for_rd <rd-id>: prints the agent holding <rd-id>'s lock, or
# "" if it isn't currently locked. Unlike cz_sole_lock_*, this disambiguates
# correctly even with several RDs claimed concurrently (standard/heavy
# profiles allow up to max_in_flight) — sole-lock only works when exactly one
# claim exists project-wide.
cz_lock_agent_for_rd() {
  local rd="$1" f
  [ -n "$rd" ] || return 0
  f="$LOCK_DIR/$rd.lock"
  [ -f "$f" ] && awk -F= '/^agent=/{print $2}' "$f"
  return 0
}

# cz_extract_rd_id <text>: prints the first RD-XXX-NN.NN[a-z] pattern found
# anywhere in <text> (a file path, a Bash command string, or an entire raw
# hook-input JSON blob), or "" if none. Tool calls that touch or reference an
# RD (file paths under evidence/<rd>/, deliverables/DEVBOOK-<rd>.md, test
# runs naming the RD, etc.) carry the id in plain text even when no
# CZ_ACTIVE_RD env var was set — this lets a hook resolve which of several
# concurrently-claimed RDs a given tool call belongs to, then look up that
# RD's own lock (see cz_lock_agent_for_rd) instead of falling back to the
# ambiguous "only one lock exists" case.
#
# state/locks/*.lock, state/heartbeats/*.hb, state/board.json, and
# telemetry/events.jsonl references are stripped BEFORE matching. Live
# incident: a completely unrelated Claude Code session merely inspecting
# RD-AIBOOTCAMP-009.01c's orphaned lock (`cat state/locks/RD-...c.lock`,
# `grep ... telemetry/events.jsonl`) had every one of its own tool calls
# misattributed to that RD's stale claim, which kept overwriting the
# heartbeat and made a genuinely dead build process look perpetually alive —
# masking the real stall for over 15 minutes. Reading or grepping these
# meta/introspection files is diagnostic activity ABOUT an RD, never work ON
# one, so an RD id appearing only inside one of these paths must not resolve
# identity. A path under a real artifact directory (evidence/, deliverables/,
# gate-records/, rd/, tests/, src/, ...) is unaffected and still matches.
cz_extract_rd_id() {
  echo "$1" \
    | sed -E 's#state/(locks|heartbeats)/[^ "'"'"',]*##g; s#state/board\.json##g; s#telemetry/[^ "'"'"',]*##g' \
    | grep -oE 'RD-[A-Za-z0-9]+-[0-9]+\.[0-9]+[a-z]?' | head -1 || true
  return 0
}

# cz_iso_to_epoch <RFC3339-UTC-string>: prints epoch seconds, or "" if
# unparseable. Tries GNU date first (Linux), falls back to BSD date (macOS).
cz_iso_to_epoch() {
  local ts="$1"
  [ -z "$ts" ] && return 0
  date -u -d "$ts" +%s 2>/dev/null && return 0
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null && return 0
  return 0
}

# cz_json_field <json-file> <top-level-key>: minimal, dependency-free scalar
# reader for flat JSON (string or bare value) — same tradeoff as cz_rd_field.
cz_json_field() {
  local file="$1" key="$2"
  # `|| true`: a missing key (grep finds nothing) must NOT fail this function —
  # under set -e + pipefail, a nonzero exit here would abort the CALLER via its
  # `x="$(cz_json_field ...)"` assignment (the same class of bug as an absent
  # config/gates.yaml aborting project-state.sh before this file existed).
  grep -oE "\"$key\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[A-Za-z0-9_.]+)" "$file" 2>/dev/null \
    | head -1 | sed -E "s/\"$key\"[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//" || true
}

# cz_json_nested_field <json-file> <parent-key> <child-key>: reads <child-key>
# from INSIDE the <parent-key> object. cz_json_field above is a flat, file-order
# `grep | head -1` — pointed at a nested document it returns whichever match
# appears FIRST in the file, regardless of which object owns it. gate-records/
# *-gate.json nests a "timestamp" under each of ai_review, security_review and
# gate_decision, so cz_json_field <f> timestamp silently returned ai_review's —
# making project-state.sh report the AI-review time as the RD's finished_date
# and inflating time_in_state_s by the whole review duration. The board and
# board/build-audit-index.py (which parses the JSON properly, in python) then
# disagreed about the same gate.
#
# Scoped by slicing the text from the parent key to the end of its object: the
# gate records this reads are flat-one-level (no nested object inside a nested
# object), so stopping at the first "}" after the parent key is sufficient and
# stays dependency-free, consistent with every other JSON helper in this file.
# Prints "" if the parent or child is absent. Always returns 0 — see the note
# above cz_sole_lock_file about best-effort lookups never failing the caller.
cz_json_nested_field() {
  local file="$1" parent="$2" child="$3"
  [ -f "$file" ] || return 0
  tr -d '\n' < "$file" 2>/dev/null \
    | grep -oE "\"$parent\"[[:space:]]*:[[:space:]]*\{[^}]*\}" \
    | head -1 \
    | grep -oE "\"$child\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[A-Za-z0-9_.]+)" \
    | head -1 \
    | sed -E "s/\"$child\"[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//" || true
  return 0
}
