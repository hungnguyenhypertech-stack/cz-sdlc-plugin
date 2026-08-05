#!/usr/bin/env python3
"""Build gate-records/index.json and telemetry rollup for the board's Audit & Outcomes tab.

Regenerate after gate-records/ or telemetry/events.jsonl change:
    python3 board/build-audit-index.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE_DIR = ROOT / "gate-records"
TELEMETRY = ROOT / "telemetry" / "events.jsonl"
DELIVERABLES_DIR = ROOT / "deliverables"

PB_RE = re.compile(r"^PB(\d+)-(.+)\.json$")
RD_RE = re.compile(r"^(RD-[A-Z0-9]+-\d+\.\d+[a-z]?)-(dor|gate)\.json$")


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
    out_path = GATE_DIR / "index.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {out_path} ({len(audit_rows)} audit rows)")


if __name__ == "__main__":
    main()
