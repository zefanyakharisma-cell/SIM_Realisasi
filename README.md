# SIM Realisasi

Management information system for the realization (implementation) of Petra Christian University's
MoUs/MoAs: one-page activity submission (Jenis Kegiatan from SIM Kerjasama's Agenda Kerjasama, IA + IR, one PDF of
transcripts/poster/documentation for mobility), Mobility verification with duplicate-student decisions, the RENSTRA
indicators (1.1, 1.19.S1, 1.19.24) with drill-down, the International Awards leaderboards, four period cut-offs
(Ganjil, Genap, Setahun kumulatif, YTD), semester freezes, and Excel export of every report. Mockup build per the
specs in [`docs/spec/`](docs/spec/) (Rules.md is authoritative; it includes the Revisi V.1 changes).

Stack: Next.js 15 (App Router) · TypeScript · Tailwind · Postgres/Supabase (business rules in SQL) · exceljs · Recharts.

## Run locally

Requires Node 22 and Postgres 16 (with `pg_trgm`, `pgcrypto`).

```bash
npm install
cp .env.example .env.local            # Supabase URL/key + DATABASE_URL (local: 127.0.0.1:54322/postgres)
npm run db:reset                      # SIMKS-shaped stub + migrations + demo seed (refuses a real SIMKS DB)
                                      # demo seed = 34 scenarios (S-01..S-34) + 200 bulk Kegiatan (RL-2026-0101..0300)
npm run dev                           # http://localhost:3000 → pick a demo account
```

The login page is a demo role switcher (`DEMO_AUTH=1`, default). Demo "today" is 2026-10-01; IO Admin can
time-travel in Pengaturan to demonstrate cutoffs, deadlines and reminders.

Turn on **Mode Demo** on the login page for an app-style onboarding tour: step-by-step pop-ups dim the screen,
spotlight one real component or button at a time and explain it. The login page, the app frame (sidebar, notifications,
account menu) and every page (dashboard, kegiatan list/detail/new/revision, verification, reports, settings tabs,
notifications, SIM Kerjasama documents) each have a tour that starts on the first visit; steps that don't apply to the
current role or screen size are skipped. The **Panduan** button replays tours or switches the mode off. The preference
and seen tours are stored per browser (localStorage); tours live in `lib/realisasi/guide/tours.ts`.

## Tests

| Command | What |
|---|---|
| `npm run test:db` | (after `SEED_BULK=0 npm run db:reset`) SQL acceptance tests (AT-01..AT-11, status machine, RLS, RENSTRA/KPIs, conflicts, awards, snapshots, adapter) |
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
