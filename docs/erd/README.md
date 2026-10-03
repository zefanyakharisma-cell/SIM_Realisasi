# SIM Realisasi: ERD & data dictionary

[`sim-realisasi-erd.html`](sim-realisasi-erd.html) holds the entity relationship diagram (inline SVG, crow's foot
notation) and the searchable data dictionary for every table, the SIM Kerjasama adapter views, the enum types and the
schema-level rules. It is generated; edit the sources and run `python3 docs/erd/generate.py`.

- [`model.py`](model.py): tables, columns, descriptions and relationships, transcribed from
  `supabase/migrations/0001_kerjasama_adapter.sql` and `0002_tables.sql`. Update it when the schema changes.
- [`template.html`](template.html): page layout, styles and the hover/search script.
- [`generate.py`](generate.py): layout, line routing and HTML output (no dependencies).
