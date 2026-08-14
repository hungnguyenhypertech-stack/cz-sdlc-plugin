#!/usr/bin/env python3
"""Build gate-records/index.json and telemetry rollup for the board's Audit & Outcomes tab.

Regenerate after gate-records/ or telemetry/events.jsonl change. Run from the
project root, or point it at one explicitly — it never infers the project from
its own install location:
    python3 board/build-audit-index.py                  # cwd is the project
    python3 .../board/build-audit-index.py /path/proj   # explicit project root
    CZ_ROOT=/path/proj python3 .../build-audit-index.py # or via env
"""
import json
import os
import re
import sys
from pathlib import Path

if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
    print(__doc__)
    sys.exit(0)

# A stray flag (leading "-") in argv[1] used to be silently accepted as a
# project-root path — e.g. `--help` resolved to a real `--help/` directory
# created in cwd, with no error and no signal that the flag was never
# recognized. Fail loudly instead: only a bare positional arg is a path.
if len(sys.argv) > 1 and sys.argv[1].startswith("-"):
    print(f"error: unrecognized argument {sys.argv[1]!r}\n\n{__doc__}", file=sys.stderr)
    sys.exit(2)

# ROOT is the PROJECT root, never this script's own location. Deriving it from
# __file__ (as this did) resolves to the plugin install directory once the
# plugin is installed from a marketplace — so it read the plugin's own
# (nonexistent) gate-records/ and then crashed trying to write index.json
# there, meaning the board's Audit & Outcomes tab had no data source at all in
# any real project. Resolution order mirrors hooks/lib/common.sh: an explicit
# override, then Claude Code's project dir, then cwd (correct when run as the
# documented `python3 board/build-audit-index.py` from the project root).
ROOT = Path(
    os.environ.get("CZ_ROOT")
    or os.environ.get("CLAUDE_PROJECT_DIR")
    or (sys.argv[1] if len(sys.argv) > 1 else "")
    or os.getcwd()
).resolve()
GATE_DIR = ROOT / "gate-records"
TELEMETRY = ROOT / "telemetry" / "events.jsonl"
DELIVERABLES_DIR = ROOT / "deliverables"

PB_RE = re.compile(r"^PB(\d+)-(.+)\.json$")
# [A-Za-z0-9]+ for the project code, matching schemas/rd.schema.json and
# schemas/telemetry-event.schema.json. This was [A-Z0-9]+ (uppercase only), so
# a lowercase-coded id — legal under both schemas — was SILENTLY dropped from
# the index: its gate record simply never appeared on the Audit tab, with no
# warning. The trailing [a-z]? stays: see the id-pattern note in
# schemas/telemetry-event.schema.json for why a suffixed id is legal.
RD_RE = re.compile(r"^(RD-[A-Za-z0-9]+-\d+\.\d+[a-z]?)-(dor|gate)\.json$")


def load(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def build_audit_rows():
    rows = []
    for f in sorted(GATE_DIR.glob("*.json")):
        data = load(f)
        if data is None:
            continue
        m_pb = PB_RE.match(f.name)
        m_rd = RD_RE.match(f.name)
        if m_pb:
            rows.append({
                "scope": "project",
                "id": f"PB{m_pb.group(1)}",
                "kind": m_pb.group(2),
                "status": data.get("status"),
                "approver": data.get("approver"),
                "timestamp": data.get("timestamp"),
                "notes": (data.get("notes") or "")[:240],
                "file": f.name,
            })
        elif m_rd:
            rd_id, kind = m_rd.group(1), m_rd.group(2)
            if kind == "dor":
                rows.append({
                    "scope": "rd",
                    "id": rd_id,
                    "kind": "dor",
                    "status": data.get("status"),
                    "approver": data.get("approver"),
                    "timestamp": data.get("timestamp"),
                    "notes": (data.get("notes") or "")[:240],
                    "file": f.name,
                })
            else:  # gate
                ai = data.get("ai_review", {}) or {}
                sec = data.get("security_review", {}) or {}
                dec = data.get("gate_decision", {}) or {}
                # Only present on an "approved" decision — written by
                # hooks/compute-estimate-variance.sh at /cz:gate step 8. See
                # schemas/gate-record.schema.json's estimate_variance
                # description: active_h (idle-gap-excluded work time) is the
                # figure variance_pct/within_pessimistic_bound are computed
                # against, not the raw wall-clock actual_h.
                ev = data.get("estimate_variance", {}) or {}
                if not isinstance(ev, dict):
                    ev = {}
                if not isinstance(ai, dict):
                    ai = {"verdict": ai}
                if not isinstance(sec, dict):
                    sec = {"verdict": sec}
                if not isinstance(dec, dict):
                    dec = {"decision": dec}
                rows.append({
                    "scope": "rd",
                    "id": rd_id,
                    "kind": "gate",
                    "ai_verdict": ai.get("verdict"),
                    "sec_verdict": sec.get("verdict"),
                    "decision": dec.get("decision"),
                    "approver": dec.get("approver"),
                    "order_enforced": data.get("order_enforced"),
                    "timestamp": dec.get("timestamp") or ai.get("timestamp"),
                    "file": f.name,
                    "estimated_h": ev.get("estimated_h"),
                    "pessimistic_h": ev.get("pessimistic_h"),
                    "actual_h": ev.get("actual_h"),
                    "active_h": ev.get("active_h"),
                    "idle_h": ev.get("idle_h"),
                    "variance_pct": ev.get("variance_pct"),
                    "within_pessimistic_bound": ev.get("within_pessimistic_bound"),
                    # See schemas/gate-record.schema.json's pending_verification: a
                    # deferred red-green proof, copied from rd/<id>.md by cz-gate.md
                    # step 7. Surfaced here so the board's Audit tab can flag it the
                    # same way it flags everything else, instead of it only being
                    # visible in the RTM.
                    "pending_verification": data.get("pending_verification"),
                    "pending_verification_reason": data.get("pending_verification_reason"),
                })
    rows.sort(key=lambda r: r.get("timestamp") or "", reverse=True)
    return rows


def build_outcome_metrics(audit_rows):
    events = []
    if TELEMETRY.exists():
        for line in TELEMETRY.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except Exception:
                continue

    gate_rows = [r for r in audit_rows if r["kind"] == "gate"]
    rd_ids = sorted({r["id"] for r in gate_rows})
    rejections_by_rd = {}
    for e in events:
        if e.get("event") == "gate_rejected" and e.get("rd"):
            rejections_by_rd[e["rd"]] = rejections_by_rd.get(e["rd"], 0) + 1

    total_gate_decisions = len(gate_rows)
    approved = sum(1 for r in gate_rows if r["decision"] == "approved")
    rejected_events = sum(rejections_by_rd.values())
    first_attempt_passes = sum(
        1 for r in gate_rows
        if r["decision"] == "approved" and rejections_by_rd.get(r["id"], 0) == 0
    )
    rework_rd_count = len(rejections_by_rd)

    project_deliverables = {"RTM": None, "WEEKLY": None, "CASE-STUDY": None}
    idx_path = DELIVERABLES_DIR / "index.json"
    if idx_path.exists():
        idx = load(idx_path) or []
        for row in idx:
            kind = (row.get("kind") or "").upper()
            base = Path(row.get("path", "")).name.upper()
            for key in project_deliverables:
                if kind.startswith(key) or base.startswith(key):
                    project_deliverables[key] = row.get("path")

    return {
        "gate_decisions_total": total_gate_decisions,
        "gate_decisions_approved": approved,
        "gate_pass_on_first_attempt_rate": (
            round(first_attempt_passes / total_gate_decisions, 3) if total_gate_decisions else None
        ),
        "rd_rework_count": rework_rd_count,
        "rd_rework_rate": round(rework_rd_count / len(rd_ids), 3) if rd_ids else None,
        "gate_rejected_events_total": rejected_events,
        "rds_with_gate_decision": len(rd_ids),
        "project_deliverables": project_deliverables,
    }


def main():
    audit_rows = build_audit_rows()
    outcome = build_outcome_metrics(audit_rows)
    out = {"audit": audit_rows, "outcome": outcome}
    # A project with no gate records yet still needs a readable (empty) index —
    # board.html fetches it unconditionally and shows a load error on a 404.
    GATE_DIR.mkdir(parents=True, exist_ok=True)
    out_path = GATE_DIR / "index.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {out_path} ({len(audit_rows)} audit rows)")


if __name__ == "__main__":
    main()
