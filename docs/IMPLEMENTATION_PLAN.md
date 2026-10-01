# SIM Realisasi — Implementation Plan (Mockup v1.0)

**Status:** Binding for all builder agents · **Companion:** `docs/CONTRACTS.md` (interface contract, wins over this file on interface details) · **Spec:** `docs/spec/*` (Rules.md wins on behaviour conflicts)

---

## 1. Overview

We build the SIM Realisasi mockup as a single Next.js 15 App Router app on top of one Postgres database. All business rules (status machine, period derivation, renewal chains, KPI math, snapshots, SLA, reminders) live in SQL in schema `realisasi`; the app is a thin, role-aware UI plus Excel exporters. Five work packages (WPs) are built **in parallel in the same directory**. Every file has exactly one owner WP. Cross-WP dependencies go only through the signatures fixed in `docs/CONTRACTS.md`.

## 2. Requirements summary (what "done" means)

- Submission wizard (Detail → Peserta → Berkas → Tinjau & Ajukan) with autosaved drafts, NRP/employee lookup, agreement picker by activity dates, IA+IR PDFs mandatory (R-07..R-22).
- Dual-track verification (Kemitraan / Mobilitas) with independent revision loops, rejection, versioned participant sets with diff (R-23..R-28).
- Post-verification IO edits with field diff log and frozen-period flag (R-29..R-31).
- Duplicate detection + linking into event groups (R-32..R-35).
- Known Activities register with suggestions, match/dismiss/nudge (R-51..R-54).
- KPI engine (1.1, 1.19.S1, 1.19.24, 1.19.S8) with drill-down, university vs unit level, live + frozen snapshots, late additions, post-freeze changes (R-36..R-59).
- SLA chips, revision reminders/escalations, deadline reminders, scheduled freeze, "time travel" via `demo_today` (R-60..R-62).
- Role-based access (R-63, R-64, Rules §10) enforced in the DB (RLS + security-definer RPCs) and mirrored in the UI.
- Excel export for every list/report, with an Info sheet; personal-data exports logged.
- SIM Kerjasama "Realisasi" tab + "no realization" flag on a minimal document list.
- Demo login role switcher with the 8 seed accounts; full seed covering S-01..S-30.
- Acceptance scenarios AT-01..AT-12 verified by SQL tests and Playwright (see §8).

## 3. Architecture changes vs. spec (binding lead decisions, already reflected in CONTRACTS.md)

| Spec says | We do (mockup) | Why |
|---|---|---|
| `@supabase/ssr`, Supabase Auth | `postgres` (postgres.js) via `DATABASE_URL`; `withUser()` sets `role authenticated` + `request.jwt.claims` per transaction; demo cookie `demo_uid` | Runs on plain Postgres 16 and on Supabase unchanged; RLS + `auth.uid()` behave identically |
| Supabase Storage | `realisasi.file_blobs` table behind `lib/storage.ts` + RPCs `storage_put/storage_get` | No storage service locally; helper is the swap point |
| pg_cron only | `realisasi.run_daily_jobs()` callable by io_admin from Pengaturan; pg_cron schedules it when available | Demo can trigger jobs after time-travel |
| Trigger `log_changes` | Diff logging inside the edit RPCs (`edit_verified_activity`, revision-phase `save_activity_draft`, `commit_participant_edit`, file RPCs) | Seeds can insert history without noise; RPCs know the actor & note |
| pgTAP | Plain psql scripts with `DO` blocks that `raise exception` | pgTAP not installed |
| `pset_status` 4 values | + `'draft'` | Unit edits a draft version before (re)submission |
| — | `activities.partnership_since`, `activities.mobility_since`, table `realisasi.job_marks` | SLA clock + notify-once dedupe |
| — | Setting `demo_today`; `realisasi.today()` / `realisasi.now_ts()` used by every rule | Time travel |

## 4. Work packages & file ownership

> **Ownership rule:** a builder creates/edits **only** files matched by its globs below. If you need something from another WP, code against the signature in CONTRACTS.md and leave a `// CONTRACT:` comment; do not create a stub in someone else's path. If a contract gap blocks you, write it in your final report (the lead resolves in Phase 3). `docs/**` belongs to the lead.

### WP-DB — database, seeds, SQL tests
Owns:
- `supabase/**` (migrations, seed, tests, `supabase/README` not required)
- `scripts/db-reset.sh`, `scripts/db-test.sh`, `scripts/db-*.sh`

### WP-FOUNDATION — project skeleton, shell, auth, shared libs
Owns:
- Root configs: `package.json`, `package-lock.json`, `tsconfig.json`, `next.config.ts`, `postcss.config.mjs`, `tailwind.config.ts`, `eslint.config.mjs`, `vitest.config.ts`, `playwright.config.ts`, `.env.example`, `.gitignore`, `middleware.ts`
- `app/layout.tsx`, `app/page.tsx`, `app/globals.css`, `app/not-found.tsx`, `app/(auth)/**`, `app/realisasi/layout.tsx`, `app/realisasi/error.tsx`, `app/realisasi/loading.tsx`, `app/realisasi/notifikasi/**`
- `components/ui/**`, `components/layout/**`, and these shared files: `components/realisasi/status-badge.tsx`, `components/realisasi/page-header.tsx`, `components/realisasi/empty-state.tsx`, `components/realisasi/export-button.tsx`, `components/realisasi/country-flag.tsx`, `components/realisasi/forbidden.tsx`, `components/realisasi/notification-bell.tsx`, `components/realisasi/demo-today-banner.tsx`
- `lib/db.ts`, `lib/session.ts`, `lib/storage.ts`, `lib/utils.ts`, `lib/realisasi/types.ts`, `lib/realisasi/status.ts`, `lib/realisasi/format.ts`, `lib/realisasi/errors.ts`, `lib/realisasi/actions/notifications.ts`, `lib/realisasi/actions/session.ts`
- `e2e/helpers.ts`, `e2e/global-setup.ts`, `e2e/foundation.spec.ts`
- Unit tests for its libs: `lib/*.test.ts`, `lib/realisasi/{status,format,errors}.test.ts`

**Only WP-FOUNDATION runs `npm install`.** Other WPs wait until `node_modules/.package-lock.json` exists before running `tsc`/`vitest`/`next`.

### WP-SUBMIT — submission wizard, activity detail, revision, files, lookups
Owns:
- `app/realisasi/kegiatan/baru/**`, `app/realisasi/kegiatan/[id]/**` (detail, `revisi/`, `edit/`, `peserta-edit/`)
- `app/api/upload/route.ts`, `app/api/files/[...path]/route.ts`, `app/api/lookup/**`, `app/api/template/**`
- `components/realisasi/wizard/**`, `components/realisasi/activity/**`
- `lib/realisasi/schemas/activity.ts`, `lib/realisasi/schemas/participants.ts`, `lib/realisasi/actions/submission.ts`, `lib/realisasi/queries/activity.ts`, `lib/realisasi/queries/lookups.ts`, `lib/rate-limit.ts`
- `e2e/submit.spec.ts`, tests next to its libs

### WP-VERIFY — queues, duplicates, known activities, activity list
Owns:
- `app/realisasi/kegiatan/page.tsx` (+ `app/realisasi/kegiatan/loading.tsx`), `app/realisasi/verifikasi/**`, `app/realisasi/kegiatan-diketahui/**`
- `components/realisasi/verify/**`, `components/realisasi/list/**`, `components/realisasi/known/**`, `components/realisasi/duplicates/**`
- `lib/realisasi/schemas/filters.ts`, `lib/realisasi/schemas/verification.ts`, `lib/realisasi/schemas/known.ts`, `lib/realisasi/actions/verification.ts`, `lib/realisasi/actions/duplicates.ts`, `lib/realisasi/actions/known.ts`, `lib/realisasi/queries/activities.ts`, `lib/realisasi/queries/known.ts`, `lib/realisasi/queries/duplicates.ts`, `lib/realisasi/participant-diff.ts`
- `e2e/verify.spec.ts`, tests next to its libs

### WP-REPORTS — dashboard, reports, exports, settings, Kerjasama tab
Owns:
- `app/realisasi/page.tsx` (+ `app/realisasi/_dashboard/**` if needed), `app/realisasi/laporan/**`, `app/realisasi/pengaturan/**`, `app/kerjasama/**`, `app/api/export/**`
- `components/realisasi/dashboard/**`, `components/realisasi/reports/**`, `components/realisasi/settings/**`, `components/kerjasama/**`
- `lib/excel/**`, `lib/realisasi/schemas/settings.ts`, `lib/realisasi/schemas/report.ts`, `lib/realisasi/actions/settings.ts`, `lib/realisasi/queries/reports.ts`
- `e2e/reports.spec.ts`, tests next to its libs

### Cross-WP imports (the only allowed ones besides FOUNDATION libs/components)
| Importer | Imports | From (owner) |
|---|---|---|
| WP-SUBMIT detail page | `PartnershipActions`, `MobilityActions`, `DuplicateActions` | `components/realisasi/verify/*` (VERIFY) |
| WP-VERIFY kemitraan queue | `ActivityDetailSummary`, `FileList` | `components/realisasi/activity/*` (SUBMIT) |
| WP-VERIFY mobilitas queue | `ParticipantTable` | `components/realisasi/activity/participant-table.tsx` (SUBMIT) |
| WP-REPORTS exports | `parseActivityFilters`, `listActivities`, `describeActivityFilters`, `parseKnownFilters`, `listKnownActivities`, `listDuplicateCandidates` | `lib/realisasi/schemas/filters.ts`, `lib/realisasi/schemas/known.ts`, `lib/realisasi/queries/*` (VERIFY) |
| Everyone | `lib/db.ts`, `lib/session.ts`, `lib/storage.ts`, `lib/realisasi/{types,status,format,errors}.ts`, `components/ui/*`, shared `components/realisasi/*` | FOUNDATION |

## 5. Phases

### Phase 0 — Contract (done)
`docs/IMPLEMENTATION_PLAN.md`, `docs/CONTRACTS.md`.

### Phase 1 — Parallel build (all WPs start immediately)

**WP-DB** (critical path; others can code against the contract before it lands)
1. `0000_bootstrap.sql` … `0004_views.sql` (stubs, enums, tables, core helpers, views) — Risk: Low. Land first so the DB can be reset early.
2. `0005_triggers.sql`, `0006_rls.sql` — Risk: Medium (RLS correctness; definer helpers to avoid recursion).
3. `0007`–`0011` RPCs (submission, files, verification, duplicates/known, admin) — Risk: Medium.
4. `0012_kpi.sql`, `0013_snapshots.sql`, `0014_reads.sql`, `0015_jobs.sql`, `0016_grants.sql`, `0017_pg_cron.sql` — Risk: High (KPI math; must match Rules §6 literally).
5. Seeds `00`…`90` incl. historical freezes — Risk: High (scenario numbers drive AT tests).
6. `scripts/db-reset.sh`, `scripts/db-test.sh`, `supabase/tests/*.sql` — all tests green on a fresh reset.

**WP-FOUNDATION**
1. `package.json` with the full dependency list (CONTRACTS §3.1), `npm install`, configs, Tailwind tokens, `globals.css`. — do this first; other WPs block on `node_modules`.
2. `lib/db.ts`, `lib/session.ts`, `lib/storage.ts`, `lib/realisasi/{types,status,format,errors}.ts` exactly per CONTRACTS §3.
3. `components/ui/*` (list in CONTRACTS §3.9), shared `components/realisasi/*`.
4. `middleware.ts`, `/login` + actions, `app/realisasi/layout.tsx` (sidebar per Design §1 with badges from `nav_counts()`), notification bell + `/realisasi/notifikasi`, demo-today banner.
5. Playwright config + `e2e/global-setup.ts` (runs `scripts/db-reset.sh`), `e2e/helpers.ts` (`loginAs`, `resetDb`), `e2e/foundation.spec.ts`.

**WP-SUBMIT**
1. Zod schemas (`activity.ts`, `participants.ts`) + server actions (`submission.ts`) + lookups queries.
2. API routes: lookups (rate-limited 60/min/user), upload, file serving, NRP template.
3. Wizard steps 1–4 with autosave (`?draft=<id>&step=n`), R-08/R-12 client hints, checklist from `submission_checklist()`.
4. Activity detail page (tabs Detail/Peserta/Berkas/Riwayat, revision banner, action bar embedding VERIFY components), revision view, IO edit pages (`edit/`, `peserta-edit/`).
5. `e2e/submit.spec.ts` (AT-04 flow, AT-10 row-level error, draft save/submit happy path).

**WP-VERIFY**
1. `filters.ts` + `queries/activities.ts` (`listActivities`) — publish early: REPORTS' activity export depends on it.
2. Activity list page with per-column filters, presets, `list-total`, export button.
3. Kemitraan queue (SLA-sorted, inline expand, approve/revise/reject dialogs), Mobilitas queue (version diff, per-row notes, transcript sheet).
4. `PartnershipActions` / `MobilityActions` / `DuplicateActions` components for the detail page.
5. Duplikat page, Kegiatan Diketahui register (create sheet, suggestions, match/dismiss/nudge).
6. `e2e/verify.spec.ts` (AT-03 flow, S-17 revision request, link duplicate, known match).

**WP-REPORTS**
1. `lib/excel/workbook.ts` (styling per Design §5, Info sheet) + export registry + `/api/export/[kind]` with access matrix (CONTRACTS §6).
2. Dashboard: period selector, 4 KPI cards (+delta), 6 charts, drill-down, frozen badge, submitter scope, drafts-near-deadline.
3. Laporan page: report list per role, preview tables, snapshot archive + detail.
4. Pengaturan tabs (Umum incl. `demo_today` + "Jalankan job harian", Kalender with freeze/refreeze, Jenis, Hari Libur).
5. `/kerjasama/dokumen` list with flag + `/kerjasama/dokumen/[id]/realisasi` tab.
6. `e2e/reports.spec.ts` (AT-01 dashboard numbers, AT-08 archive, AT-09 S8 card, AT-11 403, AT-12 export row count).

### Phase 2 — Integration (lead, after all WPs report)
1. `npm run db:reset && npm run test:db` — all green.
2. `npm run typecheck && npm run lint && npm run build` — fix cross-WP signature drift (owner of the file fixes it).
3. `npm test` (vitest) and `npm run test:e2e` (Playwright, workers = 1, DB reset in global setup and in `beforeAll` of specs that assert seed numbers).

### Phase 3 — Acceptance & polish
Walk AT-01..AT-12 (table §8) in the browser with the role switcher; empty/loading/error states per Design §4; a11y checks per Design §6.

## 6. Testing strategy

| Level | Tool | Location | Owner |
|---|---|---|---|
| SQL acceptance (KPI numbers, status machine, RLS, snapshots, jobs) | psql + `DO` blocks, each file wrapped in `begin … rollback` | `supabase/tests/*.sql`, run by `npm run test:db` | WP-DB |
| Lib unit tests (zod schemas, status/format helpers, error parsing, participant diff, excel builders) | vitest | `lib/**/*.test.ts` | owner of the lib |
| E2E journeys | Playwright (chromium, workers 1) | `e2e/*.spec.ts` | per WP |
| Export integrity | Playwright downloads workbook, reads with `exceljs`, compares row count with `[data-testid=list-total]` | `e2e/reports.spec.ts` | WP-REPORTS |

## 7. Risks & mitigations

- **Parallel edits collide** → strict ownership globs (§4); only FOUNDATION touches `package.json`; no stubs in foreign paths.
- **Cross-WP signature drift** → all shared types in `lib/realisasi/types.ts` (FOUNDATION) copied verbatim from CONTRACTS §3.5; Phase 2 typecheck catches drift.
- **KPI math disagreement between dashboard, exports and snapshots** → single SQL source (`compute_kpis` / `kpi_items`); UI and Excel never recompute KPIs in TS.
- **RLS recursion / performance** → policies call `security definer` helpers (`can_view_activity` etc.) with fixed `search_path`; helpers read tables directly.
- **postgres.js type parsing** (dates shifting by timezone, bigint as string) → `lib/db.ts` registers parsers: `date` → `'YYYY-MM-DD'` string, `timestamptz` → ISO string, `int8`/`numeric` → number (CONTRACTS §3.2).
- **Time travel breaks seeds** → SLA seed timestamps computed from `realisasi.today()` at seed time; historical scenarios use fixed dates before 2026-10-01; tests that need a specific "today" set `demo_today` inside their rolled-back transaction.
- **Seed numbers change during dev** → SQL tests assert scenario-specific facts (items of S-13/S-14 event group, D31240187 contribution, specific chain IDs), not global totals.
- **recharts + React 19 peer warning** → FOUNDATION adds `"overrides": { "react-is": "^19.0.0" }`.
- **Next 15 async `params`/`searchParams`** → all pages `await props.params` / `await props.searchParams`.

## 8. Acceptance mapping (AT-01..AT-12 → where verified)

| AT | Seed | SQL test (WP-DB) | E2E / UI (owner) |
|---|---|---|---|
| AT-01 dedupe vs unit double-count | S-13 (FTI) + S-14 (Informatika), 12 shared students, linked, Ganjil 2026/2027 | `20_kpi_1_1.sql`: university `kpi_items` 1.1 outbound rows for the S-13/S-14 event group = 12; `compute_kpis(... p_unit_id=>10)` outbound = 12; `p_unit_id=>11` outbound = 12 | `reports.spec.ts`: ua-fti dashboard Live → card 1.1 outbound 12; kaprodi-informatika → 12 (REPORTS) |
| AT-02 per person per event | S-15a/S-15b with D31240187 | `20_kpi_1_1.sql`: 1.1 items for AY 2025/2026 Genap contain 2 refs with nrp D31240187 | — |
| AT-03 dual-track independence | S-16 (Partnership approved, Mobility revision) | `10_status_machine.sql`: status `revision_requested`; unit creates v2 + resubmits; mobility approves → `verified`; v1 status `revision_requested`, unchanged rows, still present | `verify.spec.ts`: ua-fti fixes S-16 Peserta → Ajukan ulang → io.mobility approves v2 → badge "Terverifikasi"; Peserta tab shows `v1` read-only (VERIFY + SUBMIT) |
| AT-04 Jenis change resets Mobility | S-17 (Joint Seminar, Partnership revision) | `10_status_machine.sql`: change type to Student Outbound + add participant + `submit_activity` → `mobility_status='pending'` | `submit.spec.ts`: ua-fbe revision flow on S-17 (SUBMIT) |
| AT-05 grace exclusion | doc 902 (start 2026-12-02) and doc 901 (start 2026-06-15) | `21_kpi_1_19_24.sql`: items for (2026-08-01, 2027-01-31, cutoff 2027-03-02): chain 902 in `grace_excluded`, not in `denominator`; Live (cutoff 2026-10-01): chain 901 in `grace_excluded` | `reports.spec.ts`: Live dashboard card shows "n dalam masa tenggang"; drill-down grace list contains doc 901's number (REPORTS) |
| AT-06 auto-renewed, no activity | doc 903 | `21_kpi_1_19_24.sql`: chain 903 in `denominator`, not in `numerator` (Live and both 2025/2026 snapshots) | — |
| AT-07 renewal chain counted once | S-20 (doc 904) + S-20b (doc 905, renewal of 904) | `21_kpi_1_19_24.sql`: 2025/2026 full-year items contain chain 904 exactly once in `denominator` and once in `numerator`; `v_activity_documents` shows original 904/905, current 905 | `reports.spec.ts`: `/kerjasama/dokumen/905/realisasi` lists both activities with "Dokumen saat kegiatan" = 904's and 905's numbers (REPORTS) |
| AT-08 late addition | S-19 verified 2026-04-15, after Ganjil 2025/2026 freeze | `30_snapshots.sql`: Ganjil 2025/26 snapshot has no item for S-19; Genap 2025/26 snapshot has S-19 items with `is_late_addition = true`; `refreeze_snapshot` keeps old row with `superseded_by` set | `reports.spec.ts`: Laporan → Arsip → Genap 2025/2026 shows S-19 in "Tambahan susulan"; snapshot workbook has sheet `Tambahan Susulan` (REPORTS) |
| AT-09 S8 | Known 1–5 matched, 6–7 unmatched intl, 8 dismissed (Ganjil 2026/27 window) | `22_kpi_s1_s8.sql`: Live S8 `unmatched_known = 2`, `reported` = count of distinct intl verified event groups; pct = reported/(reported+2) | `reports.spec.ts`: S8 card shows "2 kegiatan belum dilaporkan" (REPORTS) |
| AT-10 unknown NRP blocks | — | `11_submission_validation.sql`: `save_participants` with unknown NRP raises `R16_NRP_NOT_FOUND` with detail rows | `submit.spec.ts`: paste `Z99999999` → Cek NRP → red row, Ajukan disabled (SUBMIT) |
| AT-11 viewer participant export | — | `40_rls.sql`: as rektorat, `select count(*) from realisasi.participant_students` = 0; `kpi_participant_rows` raises `AUTH_FORBIDDEN` | `reports.spec.ts`: as rektorat GET `/api/export/participants` → 403; Laporan has no "Daftar peserta" (REPORTS) |
| AT-12 export = on-screen rows | — | — | `reports.spec.ts`: Kegiatan list with filters (`status=verified&ay=1`) → Unduh Excel → sheet `Kegiatan` data rows = `list-total`; Info sheet lists the filters (REPORTS, uses VERIFY list) |

## 9. Success criteria
- [ ] `npm run db:reset` builds the DB from zero on plain Postgres 16; re-running seeds is idempotent.
- [ ] `npm run test:db` green (all files in `supabase/tests`).
- [ ] `npm run typecheck`, `npm run lint`, `npm run build` green.
- [ ] `npm test` and `npm run test:e2e` green.
- [ ] Each of the 8 accounts sees exactly the navigation of Design §1 and the data of Rules §10.
- [ ] Every list and report has a working "Unduh Excel" whose rows equal the screen.
- [ ] Time travel to 2027-03-02 + "Jalankan job harian" freezes Ganjil 2026/2027 with doc 902 grace-excluded.
