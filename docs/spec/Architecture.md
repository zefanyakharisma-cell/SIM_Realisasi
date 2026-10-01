# SIM Realisasi — Architecture
**Version:** 1.0 (Mockup) · Next.js (App Router) on Vercel + Supabase · shares project & database with the SIM Kerjasama demo

---

## 1. Principles
1. **One database, two systems.** Realisasi lives in schema `realisasi` beside SIM Kerjasama's `public`; it only reads Kerjasama data through views/functions (Schema §5), never writes it.
2. **Business rules in the database.** Status derivation, period derivation, chain resolution, and KPI math are SQL (triggers/functions) so the UI, exports, and snapshots can never disagree.
3. **External systems behind an RPC boundary.** BAAK/HR are mocked, but the app only calls `lookup_students` / `lookup_employees`, so production swaps the implementation, not the app.
4. **Frozen means frozen.** Snapshots are written once; corrections create a new superseding snapshot with a reason.
5. **Privacy by default.** Participant data and transcripts sit behind RLS and private storage; every personal-data export is logged.

---

## 2. Stack
| Layer | Choice |
|---|---|
| Frontend | Next.js 15 App Router, TypeScript, Tailwind, shadcn/ui (same component kit as SIM Kerjasama demo) |
| Forms & validation | react-hook-form + zod (schemas shared client/server) |
| Data | Supabase Postgres, RLS, SQL functions; `@supabase/ssr` client |
| Auth | Supabase Auth (shared with SIM Kerjasama); demo role switcher |
| Files | Supabase Storage, private buckets, signed URLs (5 min) |
| Jobs | `pg_cron` for reminders, SLA, freezes; Postgres triggers for duplicate scan |
| Excel | `exceljs` in Next.js route handlers (server-side, streamed) |
| Charts | Recharts |
| Email | `email_outbox` table (mockup) → Resend in production |
| Fuzzy matching | `pg_trgm` extension (`similarity()`) |

---

## 3. Module map
```text
app/
  (auth)/login
  realisasi/
    page.tsx                      -> dashboard (KPI cards, charts, period selector)
    kegiatan/                     -> activity list (role-filtered) + export
      baru/                       -> submission wizard (Detail → Peserta → File → Review)
      [id]/                       -> activity detail (tabs: Detail, Peserta, File, Riwayat)
      [id]/revisi/                -> unit revision view
    verifikasi/
      kemitraan/                  -> Partnership queue
      mobilitas/                  -> Mobility queue (+ version diff)
      duplikat/                   -> duplicate candidates
    kegiatan-diketahui/           -> Known Activities register
    laporan/                      -> KPI drill-downs, snapshot archive, all exports
    pengaturan/                   -> settings, calendar, Jenis master, holidays (io_admin)
  kerjasama/dokumen/[id]/realisasi -> tab injected into SIM Kerjasama document detail
  api/
    export/[kind]/route.ts        -> Excel exports
    lookup/students/route.ts      -> proxies RPC (rate-limited)
    lookup/employees/route.ts
lib/
  realisasi/                      -> typed queries, zod schemas, status helpers
  excel/                          -> workbook builders (one per export kind)
supabase/
  migrations/                     -> schema, functions, triggers, RLS, cron
  seed/                           -> accounts, calendar, Jenis, mock registries, scenarios
```

---

## 4. Key flows (technical)

### 4.1 Submission
1. Wizard autosaves a `draft` activity after Detail step (server action).
2. Agreement picker → `rpc('documents_valid_between', {start, end})`: documents (any status except rejected/in_process) whose validity overlaps the activity dates; results include partner + country + whether submitter unit is in scope.
3. Peserta step → paste/upload NRPs → `/api/lookup/students` → returns found / not found / inactive. Not found blocks; graduated/inactive shows a warning (allowed — activity may predate graduation).
4. Inbound transcripts upload to `realisasi-transcripts/{activity_id}/{version}/{nrp}.pdf`.
5. Submit = single transactional RPC `submit_activity(id)`:
   - validates completeness (Rules §4), IA+IR present, end_date ≤ today;
   - creates participant set v1 (if any rows) with `pending`;
   - sets `partnership_status = pending`, `mobility_status = pending | not_required`;
   - writes log, notifications, outbox emails;
   - runs duplicate scan.

### 4.2 Verification
- Each action is an RPC (`partnership_approve`, `partnership_request_revision`, `partnership_reject`, `mobility_approve`, `mobility_request_revision`) that checks team membership, current track status, and writes logs + notifications atomically.
- Overall status is recomputed by trigger, never set by the app.

### 4.3 Duplicate detection
- On submit: candidate if another non-rejected activity shares ≥1 `chain_id`, dates overlap within `dup_date_window_days`, and `similarity(name) ≥ dup_name_similarity` → insert `duplicate_candidates`, notify Partnership.
- `link_duplicates(a, b)` → re-points all activities of b's event group to a's group; logs on both.

### 4.4 Snapshot freeze
- `pg_cron` daily 01:00 WIB: for each semester whose `cutoff_date = today` and no live snapshot → `freeze_snapshot(ay, kind)`.
- `freeze_snapshot` computes all 4 KPIs (Schema §5.2) for the window, writes `values`, `settings_used`, and all contributing IDs to `kpi_snapshot_items`; flags items whose `verified_at` > previous snapshot's `frozen_at` but whose date falls in that previous window as `is_late_addition`.
- `refreeze_snapshot(id, reason)` (io_admin) creates a new snapshot and sets `superseded_by` on the old one.

### 4.5 Reminders & SLA (pg_cron, daily 07:00 WIB)
| Job | Logic |
|---|---|
| Verification SLA | business days since track became `pending` (excludes weekends + `holidays`); notify at yellow/red thresholds once each |
| Unit revision | reminder at `revision_reminder_days`; escalate to IO at `revision_escalate_days` |
| Reporting deadline | drafts with `reporting_deadline` in 7 days, today, and every 7 days after |
| Notifications fan-out | writes `notifications` + `email_outbox` |

### 4.6 Excel exports
- `GET /api/export/{kind}?filters=…` → server checks role → builds workbook with `exceljs` → streams `.xlsx`.
- Every workbook has a **Info** sheet: export kind, filters, generated by, generated at, data as-of (live or snapshot id).
- Personal-data exports (participants, snapshot participant sheet) write `export_log` with `contains_personal_data = true`.
- Filenames: `SIM-Realisasi_{kind}_{period}_{yyyyMMdd-HHmm}.xlsx`.

---

## 5. Security
- **RLS** on every `realisasi` table (Schema §6). Team membership checked via `realisasi.team_members`.
- **Storage buckets**
  - `realisasi-files` (IA, IR, evidence): readable by IO, viewers (verified only), and own/co-units.
  - `realisasi-transcripts`: readable only by Mobility, IO Admin, and the submitting unit.
- **Lookup endpoints** rate-limited (60 req/min/user) to prevent registry scraping.
- **Service role** used only in cron/RPC `security definer` functions, never in the browser.

---

## 6. Production BAAK/HR contract (to hand to PSI)
```text
GET /students?nrp=D31240187,X01260012
→ 200 [{ nrp, full_name, faculty_code, faculty_name, prodi_name,
         category: regular|inbound_exchange, home_institution, home_country_code,
         status: active|graduated|inactive }]

GET /employees?id=PG204517
→ 200 [{ employee_id, full_name, unit_name, position, status }]
```
Replace the bodies of `realisasi.lookup_students` / `lookup_employees` (or the route handlers) — no other change needed.

---

## 7. SIM Kerjasama integration points
| Where | How |
|---|---|
| Document detail → Realisasi tab | `v_activity_documents` filtered by `chain_id = chain_root(doc)`; verified activities only (all statuses for IO) |
| Active list "no realization" flag | `kpi_1_19_24` classification per chain for current academic year; hidden while in grace period |
| Renewal evaluation | realization summary component (count per year, last activity, total students) |
| Shared masters | units, countries, partners, profiles — read-only |

---

## 8. Environments & deployment
- One Supabase project (demo) + Vercel project; preview deployments per branch.
- Migrations via Supabase CLI; seeds idempotent and re-runnable (`supabase db reset` restores the demo).
- Demo "time travel": io_admin setting `demo_today` (mockup only) so cutoffs, deadlines, and SLAs can be demonstrated without waiting.

---

## 9. Testing
| Level | Coverage |
|---|---|
| SQL (pgTAP) | every KPI function against seed scenarios with expected numbers; triggers; RLS per role |
| Server actions | zod validation, submit/verify transitions, forbidden transitions |
| E2E (Playwright) | scenario walkthroughs S-13/14, S-16, S-19, S-20 using the role switcher |
| Export | open each workbook, assert sheet names, row counts match on-screen counts |
