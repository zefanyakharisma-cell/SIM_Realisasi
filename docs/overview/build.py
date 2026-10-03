#!/usr/bin/env python3
"""Assemble docs/overview/sim-realisasi-brief.html: the project brief for the IO Director and programmers.

Pulls in the BPMN renders (docs/bpmn/*.svg) and the ERD + data dictionary (docs/erd/model.py) so the brief never
drifts from those sources. Run the two generators first, then this:
  python3 docs/bpmn/generate.py && python3 docs/overview/build.py
"""
from __future__ import annotations

import html
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(DOCS, "erd"))

import generate as erd  # noqa: E402  (docs/erd/generate.py)
from model import DOMAINS, ENUMS, RELS, TABLES, VIEWS  # noqa: E402

esc = lambda s: html.escape(str(s), quote=True)  # noqa: E731


def bpmn_svg(name: str) -> str:
    s = open(os.path.join(DOCS, "bpmn", f"{name}.svg"), encoding="utf-8").read()
    s = re.sub(r' width="\d+" height="\d+"', "", s, count=1)
    # both diagrams share gradient/marker ids; prefix them so each inline SVG keeps its own
    prefix = name.split("-")[-1][:4]
    for ident in ("gTask", "gGw", "shadow", "arr", "marr", "mstart"):
        s = s.replace(f'id="{ident}"', f'id="{prefix}{ident}"').replace(f"url(#{ident})", f"url(#{prefix}{ident})")
    return s


def main():
    boxes, height = erd.layout()
    page = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
    n_cols = sum(len(t[4]) for t in TABLES)
    repl = {
        "%%BPMN1%%": bpmn_svg("sim-realisasi-pengajuan-verifikasi"),
        "%%BPMN2%%": bpmn_svg("sim-realisasi-tutup-semester"),
        "%%ERD%%": erd.svg(boxes, height, erd.edges(boxes)),
        "%%DICT%%": erd.dictionary(),
        "%%ENUMS%%": "".join(f"<tr><td><code>{esc(n)}</code></td><td><code>{esc(v)}</code></td><td>{esc(d)}</td></tr>"
                             for n, v, d in ENUMS),
        "%%VIEWS%%": "".join(f"<li><code>{esc(n)}</code> {esc(d)}</li>" for n, d in VIEWS),
        "%%CHIPS%%": "".join(f'<button type="button" class="chip" data-dom="{k}" aria-pressed="false">'
                             f'<span class="dot d-{k}"></span>{esc(v)}</button>' for k, v in DOMAINS.items()),
        "%%N_TABLES%%": str(len(TABLES)), "%%N_COLS%%": str(n_cols),
        "%%N_RELS%%": str(len(RELS)), "%%N_ENUMS%%": str(len(ENUMS)),
    }
    for k, v in repl.items():
        page = page.replace(k, v)
    out = os.path.join(HERE, "sim-realisasi-brief.html")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print("wrote", out, len(page))


if __name__ == "__main__":
    main()
