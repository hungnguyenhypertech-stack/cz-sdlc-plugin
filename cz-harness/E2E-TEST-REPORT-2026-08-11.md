# CZ-Harness Full Test Report — 2026-08-11

**Version tested:** 1.0.24-phase0 (commit `60f0b17`)
**Scope:** hook/guard unit tests, schema & config validation, board/report rendering, end-to-end 8-scenario SDLC pattern run.
**Test artifacts (untracked, not committed):**
- `hooks/tests/test-guard-claim-lock.sh`, `test-guard-state-transition.sh`, `test-guard-role-boundaries.sh`, `test-restamp-lock.sh`, `test-compute-estimate-variance.sh`
- `_test-harness-run/` — E2E fixture project (`TEST1`), gitignored

## Coverage summary

| Stream | Result |
|---|---|
| Existing hook suite (13 files) | 103/103 assertions pass, no regressions |
| New hook tests (5 files, gap-fill) | 111 assertions — 109 pass, 2 fail by design (documents bug #4 below) |
| Schema well-formedness (5 files) | 5/5 valid draft-07 |
| Schema vs. real-data validation | see findings #12-14 |
| Config cross-checks (hazard-paths<->gates.yaml, id-scheme<->TRACEABILITY.md) | clean |
| Hooks wiring integrity | clean, no orphans |
| Board/report rendering (all 5 tabs + `build-audit-index.py`) | clean, metrics exact-match on hand-computed values |
| E2E - 8 scenarios | 6 PASS, 2 PARTIAL (scenario 2 blocked by bugs #2/#3; scenario 5 partial on schema, bug #8) |

---

## Fix sequence

Ordered so each fix either unblocks a later one or stands alone; do them in this order.

### P0 - blocks core functionality

**1. Approval forgery bypass - `hooks/guard-role-boundaries.sh:11`**
`CONTENT` extraction isn't escape-aware, truncates at the first `\"`. Confirmed live: `{"content":"{\"human_approved\": true}"}` written to `gate-records/**` exits 0 (should deny). Defeats the human-approval-forgery check (line 54) and the sub-pm approval-verb ban (line 128).
**Fix:** replace the extraction pattern with the escape-aware one already used at line 104 for the telemetry check:
```bash
# before (line 11, roughly):
CONTENT=$(echo "$INPUT" | grep -o '"content"[[:space:]]*:[[:space:]]*"[^"]*"')
# after -- reuse line 104's pattern:
CONTENT=$(echo "$INPUT" | grep -oE '"content"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"')
```
Verify with the 2 known-failing assertions in `hooks/tests/test-guard-role-boundaries.sh` -- they should flip to passing.

**2. `green->ai_review` requires a file no command ever writes - `hooks/guard-state-transition.sh:79`**
Requires `deliverables/coverage/<rd-id>.md` to exist. No step in `commands/cz-build.md` or `commands/cz-gate.md` produces it. Following the documented playbook exactly, every RD hard-stops at `green`.
**Fix -- decide the intent first, then do one of:**
- (a) If a coverage artifact was genuinely meant to exist before AI review: add a step to `cz-build.md`'s Log/Gate handoff that has `dev` or `test-designer` write `deliverables/coverage/<rd-id>.md` (a short coverage note) before requesting the `green->ai_review` transition.
- (b) If the requirement is stale/aspirational: drop it from `guard-state-transition.sh:79`.
Given how core this path is, treat as a blocking decision -- don't guess silently.

**3. Light-profile red-skip is unreachable in any real project - `hooks/guard-state-transition.sh:53`**
Profile-detection grep is unanchored and unbounded, so against the shipped `standard`/`heavy` `gates.yaml` it can never match `light`. Only "works" against the unit test's one-line fixture.
**Fix:** anchor and take the first match, same style as `project-state.sh:17`:
```bash
# before:
grep -oE 'profile:[[:space:]]*[a-z]+' config/gates.yaml
# after:
grep -m1 -oE '^profile:[[:space:]]*[a-z]+' config/gates.yaml
```

**4. `guard-red-before-green.sh` has no `red_skipped` branch at all**
Even once #3 is fixed and the state transition is allowed, the `src/**` Write is still denied -- the hook's own error message points at "docs/LIGHTWEIGHT-MODE.md for the one named exception" but implements no exception.
**Fix:** add an early-allow branch mirroring the same three-condition check `guard-state-transition.sh` already does (`profile:light` AND `layer:1` AND `red_skipped:true` on the RD frontmatter) -- if all three hold, skip the red-log requirement and allow the write.

### P1 - silent enforcement risk

**5. Fail-open, whitespace-sensitive JSON extraction across 11 hooks**
`sed -E 's/.*:"(.*)"/\1/'` breaks silently (hook falls through to exit 0 = **allow**) if there's any whitespace after the JSON colon. Affects: `guard-pipeline-order.sh:25`, `guard-state-transition.sh:10`, `guard-red-before-green.sh:15`, `guard-rd-freeze.sh:11`, `guard-role-boundaries.sh:10`, `detect-hazard.sh:10`, `render-deliverable.sh:15`, `emit-telemetry.sh:12`, `warn-decision-coverage.sh`, `warn-freshness.sh`, `warn-rd-changelog.sh`. Not currently triggered (Claude Code emits compact JSON), but one formatting change away from silently disabling every guard project-wide.
**Fix (do once, centrally):** add a single hardened extractor to `hooks/lib/common.sh` and have all 11 scripts call it instead of their own inline `sed`/`grep`:
```bash
# hooks/lib/common.sh
cz_json_field() {  # $1=field name, reads INPUT json from stdin or $2
  local field="$1" json="${2:-$(cat)}"
  printf '%s' "$json" | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}
```
Then in each hook: `CONTENT=$(cz_json_field content "$INPUT")` etc. This also fixes #1 as a side effect if done first -- consider doing #5 before #1 and dropping #1's standalone patch.

### P2 - data integrity / schema gaps

**6. `content_hash` quoting mismatch - `hooks/guard-red-before-green.sh:107`**
`cz_rd_field` returns the value *with* surrounding quotes (matches the shipped `rd-template.yaml`'s quoting), but the comparison does `grep -q "$RD_HASH" "$RED_LOG"` against unquoted log text -- reported as never matching in one code path. **Note:** the E2E run's own scenario 3 (standard profile, full red-green) succeeded through this exact hook, so verify directly before patching -- may be conditional on RD id format or a specific quoting style.
**Fix (once confirmed):** strip quotes consistently at the point of comparison:
```bash
RD_HASH="${RD_HASH%\"}"; RD_HASH="${RD_HASH#\"}"
```

**7. `ai_review->red` transition contradiction - `guard-state-transition.sh:83` vs `commands/cz-gate.md` step 8**
Command doc says on rejection, set `state: red` directly ("do not use `rejected`"); the transition table has no `ai_review->red` edge, only `ai_review->rejected`. Following the doc as written gets denied.
**Fix:** pick one and align the other -- either add `ai_review->red` to the transition table, or correct `cz-gate.md` step 8 to route through `rejected->red`. Recommend keeping `rejected` as an explicit intermediate state (better audit trail) and fixing the doc.

**8. Governance-bypass fields unrepresentable in schema**
`cz-rd.md:197` mandates emitting `rd_auto_committed` (telemetry event) and setting `human_gates_bypassed: true` (RD field) when an unattended run auto-commits an RD split. Neither fits the schemas: `telemetry-event.schema.json`'s `event` enum doesn't include `rd_auto_committed`; `rd.schema.json` has `additionalProperties:false` and no `human_gates_bypassed` property.
**Fix:**
```jsonc
// telemetry-event.schema.json -- add to event enum:
"rd_auto_committed"
// rd.schema.json -- add optional property:
"human_gates_bypassed": { "type": "boolean" }
```

**9. `board-state.schema.json` `phases[].artifact` doesn't support multi-deliverable phases**
Still typed `["string","null"]` only; `project-state.sh` emits a JSON array for the Risk phase (RISK-*.md + DELEGATION-MAP-*.md). `gate-record.schema.json`'s `phaseGateRecord` already solved this with an `artifact`/`artifacts` split -- port the same fix. Confirmed independently by both the schema-validation pass and the E2E run; **not** addressed by the 1.0.24 fix commit.
**Fix:**
```jsonc
"artifact": { "type": ["string", "null"] },
"artifacts": { "type": "array", "items": { "type": "string" } }
```
and update `project-state.sh` to emit `artifacts` (array) when there's more than one, `artifact` (string) otherwise -- mirroring whatever convention `gate-record.schema.json`'s consumer already expects.

**10. Hazard serialization is claim-time only - `hooks/guard-claim-lock.sh`**
Denies claiming a hazard RD while other locks are held, but does not stop a *new, non-hazard* claim while a hazard RD is already running -- so "hazard runs alone" only holds at the hazard RD's own claim moment, not for its whole duration.
**Fix:** on every claim attempt (not just hazard-RD claims), check whether any currently-held lock belongs to a hazard RD; if so, deny regardless of the new RD's own hazard status.

**11. `evidence.red_log: null` read as literal string `"null"` - `hooks/guard-red-before-green.sh:57-63`**
Produces a nonsense `DENIED: no red log at <root>/null` instead of the correct "no red log recorded" message. `project-state.sh:66-70` already has the right null-guard pattern for this class of field.
**Fix:** port `project-state.sh`'s null-check (treat literal string `"null"` from a missing/JSON-null field as "absent", not as a path component) into `guard-red-before-green.sh` before constructing the log path.

**12. `cz-init.md:14` doc doesn't match what `project-state.sh` actually writes**
Doc describes seeding `board.json` as `{project, wave, gate_profile, concurrency_mode, rds:{}}`; the hook's first `PostToolUse` overwrites it with a different shape (`profile`, `rds:[]`, no `gate_profile`/`concurrency_mode`/`wave`). `board-state.schema.json` agrees with the hook, not the doc.
**Fix:** update `cz-init.md:14`'s described shape to match the hook/schema (documentation-only fix, no code change).

### P3 - schema/doc polish

**13. `gate-record.schema.json` findings fields typed too strictly**
`ai_review.findings`/`security_review.findings` are typed as string arrays; every real record writes free text. One real verdict value, `needs-fixes-then-pass`, isn't in the `["pass","fail"]` enum.
**Fix:**
```jsonc
"findings": { "oneOf": [ { "type": "string" }, { "type": "array", "items": { "type": "string" } } ] }
// and add to verdict enum:
"needs-fixes-then-pass"
```

**14. `telemetry-event.schema.json` agent enum missing `"cz-build"`; 5 deprecated event names still present**
509 real lines use `agent:"cz-build"`. Decide: if it's a legitimate emitter identity, add it to the enum; if it's a bug (should be `dev` or `test-designer`), fix the emitter instead of the schema. Also remove or properly deprecate: `heartbeat_transition`, `rd_claimed`, `lock_released`, `claimed`, `green`, `build_blocked` (175 lines total using these).

**15. `plugin.json` stale manifest claim**
Description still says "7 packaged skills" including a `telemetry` skill that doesn't exist on disk (actual: 6 -- `devbook`, `gate-engine`, `rd-decomposition`, `sdd-loop`, `traceability`, `viva-prep`).
**Fix:** update the description/changelog text to say 6.

---

## Full findings detail by stream

### Stream 1 - Hook/guard unit tests
- Existing suite: 13 files, 103/103 assertions, matches the 1.0.24 changelog's own claim exactly, no regressions.
- New tests written: `test-guard-claim-lock.sh` (20/20), `test-guard-state-transition.sh` (44/44 -- mid-run discovered `green->ai_review` now also requires the coverage file per bug #2, and `superseded` was added as a second terminal state; both accounted for), `test-guard-role-boundaries.sh` (14 pass / 2 fail-by-design, documenting bug #1), `test-restamp-lock.sh` (14/14), `test-compute-estimate-variance.sh` (17/17).

### Stream 2 - Schema & config validation
- All 5 schemas valid draft-07.
- `rd.schema.json` vs real `rd/*.md`: dominant failure cause is production RDs keeping `statement`/`ac[]` in the Markdown body (`## Statement` / `## Acceptance Criteria` sections), not YAML frontmatter -- a structural mismatch between how the schema validates and how RDs are actually authored, separate from the id-pattern issue that 1.0.24 already fixed.
- `gate-record.schema.json`: 47/58 real records pass (see bug #13 for the rest).
- `state/board.json`: fails on `phases[6].artifact` (see bug #9).
- `telemetry/events.jsonl`: ~5630/7722 lines pass (see bug #14).
- `tests/.meta/*.yaml` (testcase.schema.json): no `.meta/` directory exists in the sampled project -- nothing to validate there.
- Config cross-checks and hooks wiring: clean, no findings.

### Stream 3 - Board/report rendering
No bugs. `build-audit-index.py`'s computed metrics (`gate_pass_on_first_attempt_rate`, `rd_rework_count`, etc.) matched hand-calculated values exactly against a synthetic fixture. All 5 `board.html` tabs rendered correctly with zero console errors across repeated auto-refresh cycles.

### Stream 4 - End-to-end 8-scenario run (project `TEST1`, `_test-harness-run/`)
1. **Init + scaffold** -- PASS, with doc mismatch (bug #12).
2. **Light-profile red-skip** -- PARTIAL, blocked by bugs #2, #3, #4. Once artificially unblocked, the skip matrix itself (allow on all-3-true, deny on each single flip) behaved exactly as documented. The subsequent AI-review rejection path also worked correctly (independent reviewer caught a stub passing against its AC).
3. **Standard profile, full red-green, six-point split** -- PASS. Profile escalation correctly gated to human-only; six-point rule correctly flagged and split a bad candidate; red-before-green correctly denied the pre-red write and allowed post-red; AI review passed with advisory findings; estimate variance computed.
4. **Hazard escalation** -- PASS except bug #10 (continuous serialization gap). Hazard telemetry, leash A+ escalation, mandatory security review (caught a real MEDIUM finding), and claim-time serial drain all worked. `guard-secrets.sh` also correctly blocked a hardcoded key during this scenario.
5. **Unattended auto-commit** -- PASS behaviorally (bypass logged as intended), FAIL on schema (bug #8); the board/RTM surfacing requirement in `cz-rd.md:197` is also unimplemented (`project-state.sh` never reads the bypass field).
6. **RTM orphan blocking** -- PASS. Correctly denied with zero/only-rejected gate records, correctly withheld WEEKLY under standard profile with orphans present, wrote `REPORT-BLOCKED-TEST1.md` instead. Note: the profile-based blocking behavior itself is prose-only in `cz-report.md` step 5, not hook-enforced -- no bug, just worth knowing it relies on the acting agent following the doc.
7. **`/cz:audit` + `/cz:rebuild-state`** -- PASS. Config cross-checks clean; state rebuild from telemetry alone diffed to only 4 wall-clock-derived fields, all RD states/counts/ids round-tripped identically.
8. **Sanity pass** -- PASS. `/cz:status`, `/cz:board`, `/cz:health-check`, `/cz:viva` all produced correct, artifact-grounded output; false-stall self-heal correctly downgraded an idle agent.

### Already fixed by 1.0.24 (commit `60f0b17`), re-confirmed working
`config/hazard-paths.yaml` now copied at init; `detect-hazard.sh` emits real RD ids instead of `"unknown"`; `project-state.sh` survives a missing `gates.yaml`; `board/` copied so `/cz:board`'s relative fetch URLs resolve; lowercase split-RD id suffixes accepted by the schema.

### Explicitly not bugs (by design)
Rejected-gate RDs retain `assigned_agent`; extreme estimate-variance percentages on a minutes-long test fixture (meaningless outside real project timescales); `cost_usd: null` when no cost-bearing telemetry exists (honest null, not fabricated); `wave` absent from a rebuilt `board.json` (documented partial-replay gap in `cz-rebuild-state.md`); Health Check tab showing hardcoded placeholder data (documented as requiring manual transcription, not live-wired).
