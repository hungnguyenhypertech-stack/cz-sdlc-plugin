#!/usr/bin/env python3
"""
cz-harness deliverable renderer. Stdlib-only (no pip deps — must run on any
box that has python3 and nothing else). Two jobs:

  render <md_path> <deliverables_root> <template_path>
      Convert one deliverables/**/*.md file to a sibling .html file using the
      shared template + stylesheet. Never fails loudly: on any parse hiccup
      it still emits *something* rather than blocking the write.

  index <deliverables_root> <template_path>
      Rebuild deliverables/index.html by scanning every *.md under
      deliverables_root (except _assets/) and reading each one's frontmatter.

See docs/DELIVERABLES.md for the frontmatter convention this depends on.
"""
import sys
import os
import re
import glob
import html as _html
import json
from datetime import datetime, timezone


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_text(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


# ---------------------------------------------------------------------------
# Frontmatter: minimal top-level "key: value" YAML between --- delimiters.
# Deliberately not a full YAML parser — see cz_rd_field in hooks/lib/common.sh
# for the same "dependency-free fallback" philosophy elsewhere in the plugin.
# ---------------------------------------------------------------------------
def parse_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    meta = {}
    i = 1
    while i < len(lines) and lines[i].strip() != "---":
        line = lines[i]
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            val = val.strip('"').strip("'")
            meta[key] = val
        i += 1
    body = "\n".join(lines[i + 1:]) if i < len(lines) else text
    return meta, body


# ---------------------------------------------------------------------------
# Markdown -> HTML. Line-based, single pass. Covers what cz-harness templates
# actually use: headers, tables, lists, blockquotes, fenced code, hr, HTML
# comments (passed through verbatim so they stay invisible), and inline
# **bold** / *italic* / `code` / [text](url). Not a general-purpose parser.
# ---------------------------------------------------------------------------
_INLINE_CODE = re.compile(r"`([^`]+)`")
_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
_BOLD = re.compile(r"\*\*([^*]+)\*\*")
_ITALIC = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)|_([^_]+)_")


def inline(text):
    text = _html.escape(text, quote=False)
    text = _INLINE_CODE.sub(lambda m: "<code>" + m.group(1) + "</code>", text)
    text = _LINK.sub(lambda m: '<a href="%s">%s</a>' % (m.group(2), m.group(1)), text)
    text = _BOLD.sub(lambda m: "<strong>" + m.group(1) + "</strong>", text)
    text = _ITALIC.sub(lambda m: "<em>" + (m.group(1) or m.group(2)) + "</em>", text)
    return text


def is_table_sep(line):
    return bool(re.match(r"^\s*\|?[\s:|-]+\|[\s:|-]*\|?\s*$", line)) and "-" in line


def split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def render_markdown(body):
    lines = body.splitlines()
    out = []
    i = 0
    n = len(lines)
    para = []

    def flush_para():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    while i < n:
        line = lines[i]
        stripped = line.strip()

        # HTML comments: pass through verbatim, invisible in the rendered page.
        if stripped.startswith("<!--"):
            flush_para()
            buf = [line]
            while i < n and "-->" not in lines[i]:
                i += 1
                if i < n:
                    buf.append(lines[i])
            out.append("\n".join(buf))
            i += 1
            continue

        # Fenced code block.
        if stripped.startswith("```"):
            flush_para()
            i += 1
            code_lines = []
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            out.append("<pre><code>" + _html.escape("\n".join(code_lines)) + "</code></pre>")
            i += 1
            continue

        # Blank line.
        if stripped == "":
            flush_para()
            i += 1
            continue

        # Horizontal rule.
        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            flush_para()
            out.append("<hr>")
            i += 1
            continue

        # Header.
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            flush_para()
            level = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (level, inline(m.group(2)), level))
            i += 1
            continue

        # Table: a row containing '|' immediately followed by a separator row.
        if "|" in line and i + 1 < n and is_table_sep(lines[i + 1]):
            flush_para()
            header_cells = split_row(line)
            i += 2
            body_rows = []
            while i < n and "|" in lines[i] and lines[i].strip() != "":
                body_rows.append(split_row(lines[i]))
                i += 1
            out.append("<table><thead><tr>" +
                        "".join("<th>%s</th>" % inline(c) for c in header_cells) +
                        "</tr></thead><tbody>" +
                        "".join("<tr>" + "".join("<td>%s</td>" % inline(c) for c in row) + "</tr>"
                                for row in body_rows) +
                        "</tbody></table>")
            continue

        # Blockquote.
        if stripped.startswith(">"):
            flush_para()
            quote_lines = []
            while i < n and lines[i].strip().startswith(">"):
                quote_lines.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            out.append("<blockquote><p>" + inline(" ".join(quote_lines)) + "</p></blockquote>")
            continue

        # Lists (unordered or ordered), consuming a contiguous block.
        um = re.match(r"^[-*+]\s+(.*)$", stripped)
        om = re.match(r"^\d+\.\s+(.*)$", stripped)
        if um or om:
            flush_para()
            ordered = bool(om)
            tag = "ol" if ordered else "ul"
            items = []
            pattern = r"^\d+\.\s+(.*)$" if ordered else r"^[-*+]\s+(.*)$"
            while i < n:
                mm = re.match(pattern, lines[i].strip())
                if not mm:
                    break
                items.append(mm.group(1))
                i += 1
            out.append("<%s>" % tag + "".join("<li>%s</li>" % inline(it) for it in items) + "</%s>" % tag)
            continue

        # Plain paragraph text.
        para.append(stripped)
        i += 1

    flush_para()
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Badge / page rendering
# ---------------------------------------------------------------------------
def slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def build_badges(meta):
    order = ["kind", "agent", "rd", "step", "verdict"]
    parts = []
    for key in order:
        val = meta.get(key)
        if not val or val.lower() in ("null", "none"):
            continue
        cls = "badge " + key
        if key == "verdict":
            cls += " verdict-" + slugify(val)
        parts.append('<span class="%s">%s: %s</span>' % (cls, key, _html.escape(val)))
    return "\n".join(parts) if parts else '<span class="badge">untagged</span>'


def render_one(md_path, deliverables_root, template_path):
    text = read_text(md_path)
    meta, body = parse_frontmatter(text)
    html_body = render_markdown(body)
    template = read_text(template_path)

    html_path = os.path.splitext(md_path)[0] + ".html"
    out_dir = os.path.dirname(html_path)
    css_path = os.path.relpath(os.path.join(deliverables_root, "_assets", "style.css"), out_dir)
    index_path = os.path.relpath(os.path.join(deliverables_root, "index.html"), out_dir)

    title = meta.get("kind") or os.path.splitext(os.path.basename(md_path))[0]
    rd = meta.get("rd")
    if rd and rd.lower() not in ("null", "none"):
        title = "%s — %s" % (title, rd)

    nav = '<a href="%s">&larr; deliverables index</a>' % index_path
    footer = "Rendered from %s &middot; regenerates automatically when the source is rewritten" % os.path.basename(md_path)

    page = (template
            .replace("{{TITLE}}", _html.escape(title))
            .replace("{{CSS_PATH}}", css_path)
            .replace("{{NAV}}", nav)
            .replace("{{BADGES}}", build_badges(meta))
            .replace("{{BODY}}", html_body)
            .replace("{{FOOTER}}", footer))

    write_text(html_path, page)
    return html_path


# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
INDEX_TEMPLATE_EXTRA_CSS = ""


def build_index(deliverables_root, template_path):
    md_files = sorted(
        p for p in glob.glob(os.path.join(deliverables_root, "**", "*.md"), recursive=True)
        if os.sep + "_assets" + os.sep not in p
    )
    rows = []
    for p in md_files:
        try:
            meta, _ = parse_frontmatter(read_text(p))
        except Exception:
            meta = {}
        rel = os.path.relpath(p, deliverables_root)
        html_rel = os.path.splitext(rel)[0] + ".html"
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        except OSError:
            mtime = ""

        def norm(v):
            return "" if v is None or v.lower() in ("null", "none") else v

        rows.append({
            "path": rel,
            "html": html_rel,
            "kind": meta.get("kind", ""),
            "agent": meta.get("agent", ""),
            "rd": norm(meta.get("rd", "")),
            "step": meta.get("step", ""),
            "verdict": meta.get("verdict", ""),
            "mtime": mtime,
        })

    write_text(os.path.join(deliverables_root, "index.json"), json.dumps(rows, indent=2) + "\n")

    data_json = json.dumps(rows)
    body = """
<div class="index-filters">
  <input id="f-text" placeholder="filter (agent, rd, kind, path)...">
  <select id="f-verdict"><option value="">any verdict</option></select>
</div>
<table id="index-table">
  <thead><tr><th>Kind</th><th>Agent</th><th>RD</th><th>Step</th><th>Verdict</th><th>Updated</th></tr></thead>
  <tbody></tbody>
</table>
<div class="index-empty" id="index-empty" style="display:none;">no deliverables yet</div>
<script>
const ROWS = %s;
const tbody = document.querySelector("#index-table tbody");
const verdictSel = document.getElementById("f-verdict");
const verdicts = [...new Set(ROWS.map(r => r.verdict).filter(Boolean))].sort();
verdicts.forEach(v => { const o = document.createElement("option"); o.value = v; o.textContent = v; verdictSel.appendChild(o); });

function render() {
  const q = document.getElementById("f-text").value.toLowerCase();
  const v = verdictSel.value;
  tbody.innerHTML = "";
  let shown = 0;
  ROWS.forEach(r => {
    const hay = (r.agent + " " + r.rd + " " + r.kind + " " + r.path).toLowerCase();
    if (q && !hay.includes(q)) return;
    if (v && r.verdict !== v) return;
    shown++;
    const tr = document.createElement("tr");
    tr.innerHTML = `<td><a href="${r.html}">${r.kind || r.path}</a></td><td>${r.agent}</td><td>${r.rd}</td><td>${r.step}</td><td>${r.verdict}</td><td>${r.mtime}</td>`;
    tbody.appendChild(tr);
  });
  document.getElementById("index-empty").style.display = shown ? "none" : "block";
}
document.getElementById("f-text").addEventListener("input", render);
verdictSel.addEventListener("change", render);
render();
</script>
""" % data_json

    template = read_text(template_path)
    css_path = os.path.join("_assets", "style.css")
    page = (template
            .replace("{{TITLE}}", "cz-harness deliverables")
            .replace("{{CSS_PATH}}", css_path)
            .replace("{{NAV}}", '<a href="../board/board.html">&larr; live board</a>')
            .replace("{{BADGES}}", '<span class="badge">%d deliverable(s)</span>' % len(rows))
            .replace("{{BODY}}", body)
            .replace("{{FOOTER}}", "Rebuilt on every deliverable write &middot; scans deliverables/**/*.md"))

    write_text(os.path.join(deliverables_root, "index.html"), page)


def main():
    if len(sys.argv) < 2:
        print("usage: render_deliverable.py render|index ...", file=sys.stderr)
        return 1
    mode = sys.argv[1]
    try:
        if mode == "render":
            md_path, deliverables_root, template_path = sys.argv[2:5]
            render_one(md_path, deliverables_root, template_path)
        elif mode == "index":
            deliverables_root, template_path = sys.argv[2:4]
            build_index(deliverables_root, template_path)
        else:
            print("unknown mode: %s" % mode, file=sys.stderr)
            return 1
    except Exception as e:
        # Never fail the underlying Write over a rendering hiccup.
        print("render_deliverable.py: %s (non-blocking)" % e, file=sys.stderr)
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
