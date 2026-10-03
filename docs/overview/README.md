# SIM Realisasi: project brief

[`sim-realisasi-brief.html`](sim-realisasi-brief.html) is the presentation page for the IO Director and programmers:
overview, users and access, the two BPMN process models, the RENSTRA indicators and International Awards, the ERD with
the data dictionary, the architecture, build/test/deploy, and the project status. A switch at the top shows the
Director view, the Programmer view, or everything.

It is assembled from the other generated docs, so rebuild it after changing them:

```bash
python3 docs/bpmn/generate.py     # process models (.bpmn + .svg)
python3 docs/erd/generate.py      # standalone ERD page
python3 docs/overview/build.py    # this brief (prose in template.html)
```
