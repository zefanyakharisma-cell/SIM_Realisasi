#!/usr/bin/env python3
"""Render docs/erd/sim-realisasi-erd.html: the ERD (inline SVG) and data dictionary from model.py.

Run: python3 docs/erd/generate.py
"""
from __future__ import annotations

import html
import os

from model import DOMAINS, ENUMS, RELS, TABLES, VIEWS

OUT = os.path.dirname(os.path.abspath(__file__))
COL_X = [40, 460, 840, 1220, 1600]
BOX_W = 280
HDR_H = 32
ROW_H = 18
GAP_Y = 34
TOP = 30
esc = lambda s: html.escape(str(s), quote=True)  # noqa: E731


def slug(t: str) -> str:
    return t.replace(".", "-").replace("_", "-")


def layout():
    boxes, col_y = {}, {c: TOP for c in range(len(COL_X))}
    for name, dom, col, _purpose, cols in TABLES:
        h = HDR_H + ROW_H * len(cols) + 8
        boxes[name] = {"x": COL_X[col], "y": col_y[col], "w": BOX_W, "h": h, "col": col, "dom": dom,
                       "cols": [c[0] for c in cols]}
        col_y[col] += h + GAP_Y
    return boxes, max(col_y.values()) + 10


def row_y(box, col):
    return box["y"] + HDR_H + ROW_H * box["cols"].index(col) + ROW_H / 2 + 2


def edges(boxes):
    """Orthogonal routes; each edge gets its own vertical slot in the gap it uses."""
    slots: dict[int, int] = {}
    out = []
    # longer vertical spans take outer slots so short hops stay close to the boxes
    order = sorted(RELS, key=lambda r: -abs(row_y(boxes[r[0]], r[1]) - row_y(boxes[r[2]], r[3])))
    for child, ccol, parent, pcol, kind in order:
        c, p = boxes[child], boxes[parent]
        yc, yp = row_y(c, ccol), row_y(p, pcol)
        if c["col"] == p["col"]:
            gap = c["col"]  # right-hand gap of this column
            k = slots.get(gap, 0); slots[gap] = k + 1
            sx = c["x"] + c["w"] + 14 + k * 11
            xc, xp = c["x"] + c["w"], p["x"] + p["w"]
        else:
            left_col = min(c["col"], p["col"])
            k = slots.get(left_col, 0); slots[left_col] = k + 1
            gap_start = COL_X[left_col] + BOX_W
            sx = gap_start + 14 + k * 11
            if c["col"] < p["col"]:
                xc, xp = c["x"] + c["w"], p["x"]
            else:
                xc, xp = c["x"], p["x"] + p["w"]
        out.append({"child": child, "parent": parent, "kind": kind, "pts": [(xc, yc), (sx, yc), (sx, yp), (xp, yp)],
                    "label": f"{child.split('.')[1]}.{ccol} → {parent.split('.')[1]}.{pcol}"})
    return out


def marker_many(x, y, toward_left: bool) -> str:
    # crow's foot touching the box edge at (x, y)
    d = -1 if toward_left else 1  # direction from box edge outward
    bx = x + d * 12
    return (f'<path d="M{bx} {y} L{x} {y-6} M{bx} {y} L{x} {y} M{bx} {y} L{x} {y+6}" class="mk"/>'
            f'<path d="M{x + d*15} {y-6} V{y+6}" class="mk"/>')


def marker_one(x, y, toward_left: bool) -> str:
    d = -1 if toward_left else 1
    return f'<path d="M{x + d*8} {y-6} V{y+6} M{x + d*13} {y-6} V{y+6}" class="mk"/>'


def svg(boxes, height, rels) -> str:
    W = COL_X[-1] + BOX_W + 40
    o = [f'<svg id="erd" viewBox="0 0 {W} {height}" width="{W}" height="{height}" role="img" '
         f'aria-label="Entity relationship diagram of SIM Realisasi">']
    for e in rels:
        pts = e["pts"]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)
        (x0, y0), (x1, _), (x2, _), (x3, y3) = pts
        o.append(f'<g class="rel {e["kind"]}" data-a="{slug(e["child"])}" data-b="{slug(e["parent"])}">'
                 f'<title>{esc(e["label"])}</title><path d="{d}" class="ln"/>'
                 f'{marker_many(x0, y0, x1 < x0)}{marker_one(x3, y3, x2 < x3)}</g>')
    for name, b in boxes.items():
        schema, tname = name.split(".")
        cols = next(t[4] for t in TABLES if t[0] == name)
        view = schema == "kerjasama"
        o.append(f'<a href="#t-{slug(name)}" class="ent d-{b["dom"]}{" view" if view else ""}" data-t="{slug(name)}">'
                 f'<title>{esc(name)}</title>'
                 f'<rect x="{b["x"]}" y="{b["y"]}" width="{b["w"]}" height="{b["h"]}" rx="6" class="box"/>'
                 f'<path d="M{b["x"]} {b["y"]+HDR_H} V{b["y"]+6} q0 -6 6 -6 H{b["x"]+b["w"]-6} q6 0 6 6 V{b["y"]+HDR_H} z" class="hdr"/>'
                 f'<text x="{b["x"]+12}" y="{b["y"]+20}" class="tn">{esc(tname)}</text>'
                 f'<text x="{b["x"]+b["w"]-10}" y="{b["y"]+20}" class="sc" text-anchor="end">{esc(schema)}{" · view" if view else ""}</text>')
        for i, (cn, ct, key, _nul, _desc) in enumerate(cols):
            y = b["y"] + HDR_H + ROW_H * i + ROW_H / 2 + 6
            k = key.split()[0] if key else ""
            badge = {"PK": "PK", "FK": "FK", "LFK": "FK", "UQ": "UQ"}.get(k, "")
            kcls = {"PK": "kpk", "FK": "kfk", "LFK": "klfk", "UQ": "kuq"}.get(k, "")
            o.append(f'<text x="{b["x"]+10}" y="{y}" class="kb {kcls}">{badge}</text>'
                     f'<text x="{b["x"]+36}" y="{y}" class="cn{" pk" if k == "PK" else ""}">{esc(cn)}</text>'
                     f'<text x="{b["x"]+b["w"]-10}" y="{y}" class="ct" text-anchor="end">{esc(ct)}</text>')
        o.append('</a>')
    o.append('</svg>')
    return "".join(o)


def dictionary() -> str:
    parts = []
    for name, dom, _col, purpose, cols in TABLES:
        schema, tname = name.split(".")
        rows = []
        refs = {(r[0], r[1]): r for r in RELS}
        for cn, ct, key, nul, desc in cols:
            ref = refs.get((name, cn))
            ref_html = (f' <a class="ref" href="#t-{slug(ref[2])}">→ {esc(ref[2].split(".")[1])}.{esc(ref[3])}</a>'
                        if ref else "")
            keys = " ".join(f'<span class="k k-{k.lower()}">{"FK*" if k == "LFK" else k}</span>' for k in key.split())
            rows.append(f'<tr><td class="c-name"><code>{esc(cn)}</code></td><td class="c-type"><code>{esc(ct)}</code></td>'
                        f'<td class="c-key">{keys}</td><td class="c-null">{"yes" if nul else "no"}</td>'
                        f'<td>{esc(desc)}{ref_html}</td></tr>')
        search = " ".join([name, purpose] + [f"{c[0]} {c[1]} {c[4]}" for c in cols]).lower()
        parts.append(
            f'<article class="tbl-card" id="t-{slug(name)}" data-dom="{dom}" data-search="{esc(search)}">'
            f'<header><span class="dot d-{dom}"></span><h3><span class="schema">{esc(schema)}.</span>{esc(tname)}</h3>'
            f'<span class="dom">{esc(DOMAINS[dom])}{" · view" if schema == "kerjasama" else ""}</span></header>'
            f'<p>{esc(purpose)}</p><div class="scroll"><table><thead><tr><th>Column</th><th>Type</th><th>Key</th>'
            f'<th>Null</th><th>Description</th></tr></thead><tbody>{"".join(rows)}</tbody></table></div></article>')
    return "".join(parts)


def main():
    boxes, height = layout()
    rels = edges(boxes)
    page = open(os.path.join(OUT, "template.html"), encoding="utf-8").read()
    n_cols = sum(len(t[4]) for t in TABLES)
    page = (page.replace("%%ERD%%", svg(boxes, height, rels))
            .replace("%%DICT%%", dictionary())
            .replace("%%ENUMS%%", "".join(f'<tr><td><code>{esc(n)}</code></td><td><code>{esc(v)}</code></td>'
                                          f'<td>{esc(d)}</td></tr>' for n, v, d in ENUMS))
            .replace("%%VIEWS%%", "".join(f'<li><code>{esc(n)}</code> {esc(d)}</li>' for n, d in VIEWS))
            .replace("%%CHIPS%%", "".join(f'<button type="button" class="chip" data-dom="{k}" aria-pressed="false">'
                                          f'<span class="dot d-{k}"></span>{esc(v)}</button>' for k, v in DOMAINS.items()))
            .replace("%%N_TABLES%%", str(len(TABLES))).replace("%%N_COLS%%", str(n_cols))
            .replace("%%N_RELS%%", str(len(RELS))).replace("%%N_ENUMS%%", str(len(ENUMS))))
    with open(os.path.join(OUT, "sim-realisasi-erd.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print("wrote sim-realisasi-erd.html", len(page))


if __name__ == "__main__":
    main()
