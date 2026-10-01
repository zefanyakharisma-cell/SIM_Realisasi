# SIM Realisasi

Management information system for the realization (implementation) of Petra Christian University's
MoUs/MoAs: activity submission with IA + IR, dual-track verification (Partnership / Mobility), the four
institutional KPIs (1.1, 1.19.S1, 1.19.24, 1.19.S8) with drill-down, semester freezes, and Excel export of
every report. Mockup build per the specs in [`docs/spec/`](docs/spec/) (Rules.md is authoritative).

Stack: Next.js 15 (App Router) · TypeScript · Tailwind · Postgres/Supabase (business rules in SQL) · exceljs · Recharts.

## Run locally

Requires Node 22 and Postgres 16 (with `pg_trgm`, `pgcrypto`).

```bash
npm install
cp .env.example .env.local            # DATABASE_URL for your local Postgres
npm run db:reset                      # SIMKS-shaped stub + migrations + demo seed
npm run dev                           # http://localhost:3000 → pick a demo account
```

The login page is a demo role switcher (`DEMO_AUTH=1`, default). Demo "today" is 2026-10-01; IO Admin can
time-travel in Pengaturan to demonstrate cutoffs, deadlines and SLAs.

## Tests

| Command | What |
|---|---|
| `npm run test:db` | SQL acceptance tests (AT-01..AT-11, status machine, RLS, KPIs, snapshots, adapter) |
| `npm test` | Vitest unit tests |
| `npm run typecheck` · `npm run lint` | TypeScript, ESLint |
| `npm run test:e2e` | Playwright journeys (resets the DB first) |

## Supabase (shared with SIM Kerjasama)

Realisasi is deployed into the SIM Kerjasama project and reads its data only through read-only views in
schema `kerjasama`; it never writes SIMKS tables. Design, mapping and deploy steps:
[`docs/SUPABASE_INTEGRATION.md`](docs/SUPABASE_INTEGRATION.md). Deploy with
`scripts/db-deploy-supabase.sh` (`--dry-run`, `--check`, deploy, `--seed-only`).

## Docs

- [`docs/spec/`](docs/spec/): PRD, Schema, Architecture, Design, Rules
- [`docs/CONTRACTS.md`](docs/CONTRACTS.md): SQL/TS interface contract (+ amendments)
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md): work packages and acceptance mapping
- [`docs/reviews/`](docs/reviews/): database, security, frontend and requirements reviews with resolutions
