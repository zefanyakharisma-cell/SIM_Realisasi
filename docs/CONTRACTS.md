# SIM Realisasi — Interface Contract (binding)

**Audience:** WP-DB, WP-FOUNDATION, WP-SUBMIT, WP-VERIFY, WP-REPORTS (see `docs/IMPLEMENTATION_PLAN.md` for ownership).
**Precedence:** Rules.md > this file > other spec docs. Where this file adds detail the spec lacks, this file is binding. If you find a contradiction with Rules.md, follow Rules.md and report it.

Contents
1. Global conventions
2. Database: files, schema deltas, helpers, triggers, RLS, views, errors
3. RPC catalogue (every function the app calls)
4. KPI engine, snapshots, read models (JSON shapes)
5. Jobs, notifications, seed fixtures
6. TypeScript: packages, `lib/` modules, components, calling conventions
7. Route map
8. API routes & Excel exports

---

## 1. Global conventions

| Topic | Rule |
|---|---|
| Time zone | Business dates are **Asia/Jakarta**. `realisasi.today()` = `coalesce(setting demo_today, (now() at time zone 'Asia/Jakarta')::date)`. `realisasi.now_ts()` = `now()` when `demo_today` is null, else `(demo_today + (now() at time zone 'Asia/Jakarta')::time) at time zone 'Asia/Jakarta'`. **Every** RPC/job uses `today()` for date rules and `now_ts()` for timestamps it writes (`submitted_at`, `verified_at`, `*_since`, `reviewed_at`, log/notification `created_at`, `frozen_at`, `nudged_at`, `resolved_at`, `uploaded_at`). Table defaults stay `now()`. |
| Real demo date | Seeds assume real today = **2026-10-01** and `demo_today = null`. |
| Dates on the wire | `date` → `"YYYY-MM-DD"` string; `timestamptz` → ISO-8601 string (`to_jsonb()` output in JSON; `lib/db.ts` parser for direct selects). |
| Ids | activities/event groups/psets/snapshots: `uuid`; documents/units/partners/types/AY/semesters: `int`; logs/files/known/notifications/candidates: `bigint` (number in TS). |
| Language | All user-facing strings Bahasa Indonesia (Design.md). Error messages from SQL are already Indonesian. |
| Function security | Every RPC: `language plpgsql` (or `sql`), `security definer`, `set search_path = realisasi, public, extensions, pg_temp`. Internal helpers start with `_` and are **not** granted to `authenticated`. |
| Permission source | DB is authoritative. UI uses `permissions` returned by `activity_detail()` and `can()` from `lib/session.ts` only to hide/disable controls. |
| Writes | Only via RPCs in §3. `authenticated` has **no** INSERT/UPDATE/DELETE on any `realisasi`, `mock_*` or `public` table. |
| Reads | Plain `select` from tables/views listed in §2.8 under RLS, or the read RPCs in §3.9. |

---

## 2. Database

### 2.1 Migration files (`supabase/migrations/`, applied in lexical order by `scripts/db-reset.sh`)

| File | Contents |
|---|---|
| `0000_bootstrap.sql` | `create extension if not exists pgcrypto; create extension if not exists pg_trgm;` Guarded creation of roles `anon`, `authenticated`, `service_role` (`do $$ … if not exists (select from pg_roles where rolname=…) then create role … nologin; …`). Guarded schema `auth` + function `auth.uid()` **only if absent** (body in §2.4). `public` stub tables with `create table if not exists` (§2.4). `grant usage on schema public to authenticated, anon; grant select on` the 7 stub tables `to authenticated`. |
| `0001_enums.sql` | `create schema if not exists realisasi;` all enums of Schema §2 **plus** `pset_status` includes `'draft'` (order: `'draft','pending','revision_requested','approved','superseded'`). |
| `0002_tables.sql` | All tables of Schema §3 with deltas §2.3; schemas `mock_baak`, `mock_hr` + their tables (Schema §4); `realisasi.file_blobs`, `realisasi.job_marks`. FK `kpi_snapshots.superseded_by` is `deferrable initially deferred`. `activities.code` default as in Schema. |
| `0003_core.sql` | `today()`, `now_ts()`, settings getters, `_raise()`, `business_days_between()`, `sla_days()`, `sla_level()`, `chain_root()`, `chain_current()`, label helpers, role helpers (`my_role`, `my_unit`, `in_team`, `is_io`, `can_view_activity`, `can_view_participants`, `_is_unit_editor`, `in_frozen_period`, `is_late_addition`), notification helpers (`_notify`, `_notify_team`, `_notify_admins`, `_notify_unit`), `_log()` (§2.5). |
| `0004_views.sql` | `v_activity_documents`, `v_chains`, `v_activity_list`, `v_known_activities`, `v_duplicate_candidates` (§2.7). |
| `0005_triggers.sql` | Triggers of §2.6. |
| `0006_rls.sql` | `alter table … enable row level security` on **every** `realisasi` table; SELECT policies (§2.8). |
| `0007_rpc_submission.sql` | `lookup_students`, `lookup_employees`, `documents_valid_between`, `save_activity_draft`, `delete_draft`, `ensure_participant_draft`, `save_participants`, `submission_checklist`, `submit_activity`, `_scan_duplicates`. |
| `0008_rpc_files.sql` | `can_read_file`, `storage_put`, `storage_get`, `register_activity_file`, `add_evidence_link`, `remove_activity_file`. |
| `0009_rpc_verification.sql` | `partnership_approve`, `partnership_request_revision`, `partnership_reject`, `mobility_approve`, `mobility_request_revision`, `edit_verified_activity`, `commit_participant_edit`. |
| `0010_rpc_duplicates_known.sql` | `link_duplicates`, `link_activities`, `dismiss_duplicate`, `unlink_activity`, `create_known_activity`, `update_known_activity`, `known_match_suggestions`, `match_known_activity`, `unmatch_known_activity`, `dismiss_known_activity`, `nudge_known_activity`. |
| `0011_rpc_admin.sql` | `update_settings`, `upsert_academic_year`, `upsert_semester`, `upsert_activity_type`, `upsert_holiday`, `delete_holiday`, `_rederive_periods`, `mark_notifications_read`, `log_export`. |
| `0012_kpi.sql` | `kpi_items`, `compute_kpis`, wrappers `kpi_1_1`, `kpi_1_19_s1`, `kpi_1_19_24`, `kpi_1_19_s8` (Schema §5.2 signatures). |
| `0013_snapshots.sql` | `freeze_snapshot`, `refreeze_snapshot`, `snapshot_late_additions`, `snapshot_post_freeze_changes`. |
| `0014_reads.sql` | `period_info`, `dashboard`, `kpi_drilldown`, `kpi_participant_rows`, `activity_detail`, `participant_version`, `participant_counts`, `nav_counts`, `agreement_realization`, `agreement_flags`, `snapshot_list`, `snapshot_detail`. |
| `0015_jobs.sql` | `run_daily_jobs`. |
| `0016_grants.sql` | `revoke all on all tables in schema realisasi, mock_baak, mock_hr from public, anon, authenticated;` `revoke execute on all functions in schema realisasi from public;` `grant usage on schema realisasi to authenticated;` `grant select` on the readable tables/views (§2.8) `to authenticated`; `grant execute` on every function listed in §3 `to authenticated` (explicit list). `grant usage, select on all sequences` **not** needed (definer). |
| `0017_pg_cron.sql` | `do $$ begin if exists (select 1 from pg_available_extensions where name='pg_cron') then create extension if not exists pg_cron; perform cron.schedule('realisasi-daily-jobs','0 18 * * *', $c$select realisasi.run_daily_jobs()$c$); end if; exception when others then raise notice 'pg_cron unavailable: %', sqlerrm; end $$;` (18:00 UTC = 01:00 WIB). |

All migrations must be re-runnable on a fresh DB only (no need for idempotency beyond the guarded bootstrap).

### 2.2 Seeds, scripts, tests

Seeds (`supabase/seed/`, applied in lexical order after migrations, **idempotent**: fixed ids + `on conflict do nothing`/`do update`, freezes guarded by "no live snapshot exists"):

| File | Contents |
|---|---|
| `00_kerjasama.sql` | `public.units`, `countries`, `partners`, `documents`, `document_partners`, `document_scope_units`, `profiles` (fixed ids §5.3). |
| `01_config.sql` | `realisasi.settings` (all keys §2.5.1), `academic_years`, `semesters`, `holidays` (ID public holidays 2025-01-01 … 2027-12-31), `activity_types` (ids 1–9 §5.3), `sdgs` (1–17, Indonesian names), `team_members`. Then `setval` all serials past seeded ids. |
| `02_registries.sql` | `mock_baak.students` (60 rows), `mock_hr.employees` (25 rows) per Schema §7.4 and §5.3 constraints. |
| `03_activities.sql` | Scenarios S-01…S-30 (+S-15b, S-20b) incl. event groups, units, documents, partner snapshots (via trigger), sdgs, external persons, files (+ tiny valid PDF blobs in `file_blobs`), participant versions/rows, logs, duplicate candidates. `setval('realisasi.activity_code_seq', 100)`. |
| `04_known.sql` | 8 known activities (§5.3). |
| `05_notifications.sql` | A few read/unread notifications per account + matching `email_outbox` rows. |
| `90_freeze.sql` | `select realisasi.freeze_snapshot(1,'ganjil_ytd','2026-03-02 01:00+07')` and `select realisasi.freeze_snapshot(1,'genap_full_year','2026-08-30 01:00+07')` — each only if no live snapshot exists for (1, kind). Runs after the S-05 post-freeze log (dated 2026-05-10) is in place. |

Scripts (WP-DB):
- `scripts/db-reset.sh`: loads `.env.local`/`.env` if present; `DATABASE_URL` default `postgresql://postgres@localhost:54322/sim_realisasi`; creates the database if missing (connect to the same server's `postgres` DB); `drop schema if exists realisasi, mock_baak, mock_hr cascade`; drops the 7 `public` stub tables `cascade` **only when** `RESET_PUBLIC_STUBS` is not `0` (default `1`); then runs every migration then every seed with `psql -v ON_ERROR_STOP=1 -q -f`. Exit non-zero on failure.
- `scripts/db-test.sh`: runs `supabase/tests/*.sql` in lexical order with `psql -v ON_ERROR_STOP=1`; prints `PASS <file>`/`FAIL <file>`; exits non-zero if any fails.

SQL tests (`supabase/tests/`, each file `begin; … rollback;`; acting as a user inline: `set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','<uuid>','role','authenticated')::text, true);` and `reset role;` to return to superuser):

| File | Covers |
|---|---|
| `01_smoke.sql` | All §3 functions exist with exact signatures; RLS enabled on all realisasi tables; `authenticated` lacks INSERT on `realisasi.activities`. |
| `10_status_machine.sql` | R-23..R-28, AT-03, AT-04, `verified_at` immutability. |
| `11_submission_validation.sql` | R-07, R-08, R-09, R-11, R-12, R-13, R-16, R-17, R-22, AT-10. |
| `20_kpi_1_1.sql` | AT-01, AT-02. |
| `21_kpi_1_19_24.sql` | AT-05, AT-06, AT-07, R-45, R-46. |
| `22_kpi_s1_s8.sql` | R-41, AT-09. |
| `30_snapshots.sql` | AT-08, R-56, R-58, post-freeze changes. |
| `40_rls.sql` | Rules §10 matrix per role; AT-11 (DB side); file access (`can_read_file`). |
| `50_jobs.sql` | SLA notify-once, reminders/escalations, deadline reminders, cutoff freeze under `demo_today`. |
| `60_duplicates_known.sql` | R-33/R-34, R-52..R-54. |

### 2.3 Schema deltas vs Schema.md (all other DDL exactly as Schema.md)

```sql
-- enums
realisasi.pset_status: add 'draft' (first value)

-- activities: extra columns
partnership_since timestamptz,   -- when partnership_status last changed (trigger)
mobility_since    timestamptz,   -- when mobility_status last changed (trigger)
-- academic_year_id / semester_id are NULLable for drafts outside any configured year (R-09 enforced at submit)

-- participant_set_versions: submitted_at default null (set on submit), status default 'draft'

-- participant_students check constraint relaxed for drafts:
check (section = 'internal' or home_institution is not null)
-- transcript presence for inbound is enforced by submit_activity (R17_INBOUND_DATA_REQUIRED)

-- new tables
create table realisasi.file_blobs (
  path       text primary key,          -- '<bucket>/<object key>', e.g. 'realisasi-files/<activity uuid>/ia/<uuid>.pdf'
  bucket     text not null check (bucket in ('realisasi-files','realisasi-transcripts')),
  data       bytea not null,
  mime       text not null,
  size_bytes int  not null check (size_bytes <= 10485760),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (split_part(path,'/',1) = bucket)
);
create table realisasi.job_marks (key text primary key, created_at timestamptz not null default now());

-- public.documents stub carries parent_id (MoA under MoU, display only; never used for chains)
```

Settings keys (`realisasi.settings.value` is jsonb scalar):

| key | type | default |
|---|---|---|
| `grace_period_months` | int | 6 |
| `reporting_deadline_days` | int | 30 |
| `sla_yellow_days` | int | 3 |
| `sla_red_days` | int | 5 |
| `revision_reminder_days` | int | 7 |
| `revision_escalate_days` | int | 14 |
| `dup_date_window_days` | int | 3 |
| `dup_name_similarity` | numeric 0–1 | 0.5 |
| `known_match_window_days` | int | 7 |
| `known_name_similarity` | numeric 0–1 | 0.4 |
| `nudge_resend_days` | int | 14 |
| `deadline_reminder_before_days` | int | 7 |
| `demo_today` | `"YYYY-MM-DD"` or JSON `null` | null |

### 2.4 Bootstrap stubs (0000)

```sql
-- only if function auth.uid() does not exist:
create schema if not exists auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                         current_setting('request.jwt.claims', true)::jsonb ->> 'sub'), '')::uuid
$$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;

create table if not exists public.units (id int primary key, name text not null, parent_id int references public.units(id),
  kind text not null check (kind in ('faculty','prodi','program','up')));
create table if not exists public.countries (code text primary key, name text not null);
create table if not exists public.partners (id int primary key, name text not null, country_code text not null references public.countries(code));
create table if not exists public.documents (id int primary key, doc_number text not null unique, title text not null,
  kind text not null check (kind in ('MoU','MoA')), status text not null check (status in ('active','archived','in_process','rejected')),
  start_date date, end_date date, auto_renewed boolean not null default false,
  predecessor_id int references public.documents(id), parent_id int references public.documents(id),
  archived_reason text, terminated_at timestamptz);
create table if not exists public.document_partners (document_id int references public.documents(id), partner_id int references public.partners(id),
  is_lead boolean not null default false, primary key (document_id, partner_id));
create table if not exists public.document_scope_units (document_id int references public.documents(id), unit_id int references public.units(id),
  primary key (document_id, unit_id));
create table if not exists public.profiles (id uuid primary key, email text not null unique, display_name text not null,
  app_role text not null check (app_role in ('submitter','io_staff','io_admin','viewer')), unit_id int references public.units(id));
```

### 2.5 Core helpers (0003) — exact signatures

```sql
realisasi.today() returns date                              -- stable
realisasi.now_ts() returns timestamptz                      -- stable
realisasi.setting_int(p_key text) returns int               -- stable
realisasi.setting_num(p_key text) returns numeric           -- stable
realisasi.settings_json() returns jsonb                     -- {key: value} of all keys except demo_today
realisasi._raise(p_code text, p_message text, p_detail jsonb default null) returns void
     -- raise exception using errcode='P0001', message = p_code || ': ' || p_message, detail = coalesce(p_detail::text, '')
realisasi.business_days_between(p_from date, p_to date) returns int
     -- count of d with p_from < d <= p_to, isodow < 6, d not in holidays; 0 if p_to <= p_from
realisasi.sla_days(p_since timestamptz) returns int         -- business_days_between((p_since at time zone 'Asia/Jakarta')::date, today()); null if p_since null
realisasi.sla_level(p_days int) returns text                -- null→null; > sla_red_days → 'red'; > sla_yellow_days → 'yellow'; else 'ok'
realisasi.chain_root(p_doc int) returns int                 -- Schema §5.1
realisasi.chain_current(p_doc int) returns int              -- Schema §5.1
realisasi.semester_label(p_semester_id int) returns text    -- 'Ganjil 2025/2026'
realisasi.my_role() returns text                            -- profiles.app_role of auth.uid(); null if none
realisasi.my_unit() returns int
realisasi.in_team(p_team realisasi.team) returns boolean    -- true if io_admin, else membership in team_members
realisasi.is_io() returns boolean                           -- my_role() in ('io_staff','io_admin')
realisasi.can_view_activity(p_activity uuid) returns boolean
     -- io → true; viewer → status='verified'; submitter → exists activity_units(unit_id = my_unit())
realisasi.can_view_participants(p_activity uuid) returns boolean
     -- io_admin → true; in_team('mobility') → true; submitter → exists activity_units(unit_id = my_unit()); else false
realisasi._is_unit_editor(p_activity uuid) returns boolean
     -- (my_role()='submitter' and activities.submitter_unit_id = my_unit()) or my_role()='io_admin'
realisasi.in_frozen_period(p_activity uuid) returns boolean
     -- exists live snapshot s (superseded_by is null) with activity.start_date between s.window_start and s.window_end
realisasi.is_late_addition(p_activity uuid) returns boolean
     -- exists live snapshot s: start_date in [s.window_start, s.window_end] and verified_at > s.frozen_at
realisasi._log(p_activity uuid, p_kind realisasi.log_kind, p_track realisasi.team, p_action text,
               p_note text default null, p_diff jsonb default null) returns bigint
     -- actor = auth.uid(); created_at = now_ts(); in_frozen_period computed for kind 'update'
realisasi._notify(p_recipient uuid, p_kind text, p_title text, p_body text, p_link text) returns void
     -- inserts notifications + email_outbox(to_email = profile email, subject = title, body = body || link)
realisasi._notify_team(p_team realisasi.team, …same…), _notify_admins(…), _notify_unit(p_unit_id int, …), _notify_viewers(…)
```
All role helpers are `security definer`, `stable`, read tables directly (no RLS recursion) and are granted to `authenticated` (policies call them).

### 2.6 Triggers (0005)

| Name | Table / timing | Behaviour |
|---|---|---|
| `trg_activities_derive_period` | activities BEFORE INSERT OR UPDATE OF start_date | sets `academic_year_id`, `semester_id` from calendar (`start_date between start_date and end_date`); sets both NULL if none (no error; R-09 enforced at submit). |
| `trg_activities_derive_deadline` | activities BEFORE INSERT OR UPDATE OF end_date, submitted_at | `reporting_deadline = end_date + reporting_deadline_days`; `is_late = submitted_at is not null and (submitted_at at time zone 'Asia/Jakarta')::date > reporting_deadline`. |
| `trg_activities_status` | activities BEFORE INSERT OR UPDATE | R-25: `submitted_at is null → 'draft'`; `partnership_status='rejected' → 'rejected'`; any track `revision_requested → 'revision_requested'`; P approved and M in (approved, not_required) → `'verified'`; else `'in_verification'`. If new status `verified` and `verified_at is null` → `verified_at = now_ts()` (R-28: never cleared/changed afterwards). Track clocks: on INSERT `x_since = coalesce(new.x_since, now_ts())`; on UPDATE if `x_status` changed and `x_since` not changed by the statement → `x_since = now_ts()`. `updated_at = now()`. |
| `trg_activity_documents_snapshot` | activity_documents BEFORE INSERT | `chain_id = chain_root(original_document_id)`; AFTER INSERT: insert one `activity_partner_snapshot` row per `document_partners` row (partner name/country copied). AFTER DELETE: delete that activity's snapshot rows for the document. |
| `trg_pset_supersede` | participant_set_versions BEFORE UPDATE OF status | when new status `approved`: previous `approved` row of same activity → `superseded` (executed before the update so `one_approved_pset` holds). |
| `trg_touch_updated_at` | settings | `updated_at = now()`. |

### 2.7 Views (0004) — all `with (security_invoker = true)` except `v_chains`

`realisasi.v_activity_documents` — Schema §5.1 plus columns `original_doc_number text`, `current_doc_number text`.

`realisasi.v_chains` (no RLS involvement; `public` only):
```
chain_id int, chain_start date, chain_end date, auto_renewed boolean, is_international boolean,
document_ids int[], doc_numbers text[] (ordered by start_date), current_document_id int, current_doc_number text,
kind text (of current doc), title text (of current doc), partner_names text[], country_codes text[] (distinct)
-- rows from documents where start_date is not null and status not in ('in_process','rejected')
```

`realisasi.v_activity_list` (the one source for every activity table, queue and activity export):
```
id uuid, code text, name text, type_id int, type_name text, direction realisasi.direction,
start_date date, end_date date, academic_year_id int, ay_label text, semester_id int, semester_label text,
mode realisasi.activity_mode, status realisasi.activity_status,
partnership_status realisasi.track_status, mobility_status realisasi.track_status,
partnership_since timestamptz, mobility_since timestamptz,
partnership_sla_days int, partnership_sla_level text,   -- only while track = 'pending', else null
mobility_sla_days int, mobility_sla_level text,
submitter_unit_id int, submitter_unit_name text, unit_ids int[], unit_names text[],
document_ids int[], document_numbers text[], chain_ids int[],
partner_names text[], country_codes text[], is_international boolean,   -- from activity_partner_snapshot (country <> 'ID')
is_late boolean, reporting_deadline date, submitted_at timestamptz, verified_at timestamptz,
created_at timestamptz, updated_at timestamptz, created_by uuid,
out_of_scope boolean,          -- any activity_documents.out_of_scope_warning
duplicate_open boolean,        -- any open duplicate_candidates row (false for roles that cannot see candidates)
event_group_id uuid, linked_count int   -- other activities in the same event group
```

`realisasi.v_known_activities`: all `known_activities` columns + `unit_name text, country_name text, matched_activity_code text, matched_activity_name text, created_by_name text, can_nudge boolean` (unit_id not null, status 'unmatched', nudged_at null or older than `nudge_resend_days`).

`realisasi.v_duplicate_candidates`: `id, score, status, resolved_by_name, resolved_at,` and for each side `a_id, a_code, a_name, a_unit_name, a_start_date, a_end_date, a_status, a_documents text[], a_participants int` / same with `b_` prefix. `*_participants` = total rows of the latest non-draft version (via definer helper, counts only).

### 2.8 RLS (SELECT policies) and grants

`grant select` to `authenticated` on: all `realisasi` tables **except** `file_blobs`, `job_marks`, `email_outbox`, `export_log` (those get a policy for io_admin and `grant select` too, but `file_blobs`/`job_marks` get no grant at all); all views in §2.7.

| Table | Policy `using (…)` |
|---|---|
| activities | `realisasi.can_view_activity(id)` |
| activity_units, activity_documents, activity_partner_snapshot, activity_sdgs, activity_external_persons, activity_files | `realisasi.can_view_activity(activity_id)` |
| event_groups | `true` |
| participant_set_versions | `realisasi.can_view_activity(activity_id)` (metadata only; rows below are restricted) |
| participant_students, participant_staff | `realisasi.can_view_participants((select activity_id from participant_set_versions v where v.id = set_version_id))` |
| activity_log | `realisasi.can_view_activity(activity_id) and realisasi.my_role() <> 'viewer'` |
| duplicate_candidates | `realisasi.is_io()` |
| known_activities | `realisasi.is_io()` |
| notifications | `recipient_id = auth.uid()` |
| settings, academic_years, semesters, holidays, activity_types, sdgs, team_members | `true` |
| kpi_snapshots, kpi_snapshot_items | `realisasi.my_role() in ('io_staff','io_admin','viewer')` |
| email_outbox, export_log | `realisasi.my_role() = 'io_admin'` |
| file_blobs, job_marks | RLS enabled, no policy, no grant |

### 2.9 Error contract

Every business error is raised through `realisasi._raise(code, message, detail)`:
`raise exception using errcode = 'P0001', message = '<CODE>: <pesan Indonesia>', detail = '<json or empty>'`.
`detail` (when present) is a JSON object; row-level errors use `{"rows":[{"section":"internal|inbound|staff","index":<0-based>,"id":"<nrp|employee_id>","code":"<CODE>"}]}`; field errors use `{"fields":["venue","city"]}`; checklist failures use `{"failures":[{"code":"…","message":"…"}]}`.

| Code | Message (Indonesian; `{x}` interpolated) | Raised by |
|---|---|---|
| `AUTH_REQUIRED` | Sesi tidak valid. Silakan masuk kembali. | any RPC when `auth.uid()` is null (except jobs/freeze run by system) |
| `AUTH_FORBIDDEN` | Anda tidak memiliki akses untuk tindakan ini. | any |
| `NOT_FOUND` | Data tidak ditemukan. | any |
| `STATE_INVALID` | Tindakan tidak dapat dilakukan pada status kegiatan saat ini. | any state check |
| `TRACK_NOT_PENDING` | Jalur verifikasi ini tidak sedang menunggu verifikasi. | verification RPCs |
| `VALIDATION_REQUIRED` | Kolom wajib belum diisi: {fields}. | draft save, known, admin |
| `VALIDATION_INVALID` | Nilai tidak valid: {field}. | any payload check |
| `END_BEFORE_START` | Tanggal selesai tidak boleh sebelum tanggal mulai. | draft save, edit |
| `R04_AGREEMENT_NOT_VALID` | Kerja sama {doc} tidak berlaku pada tanggal kegiatan. | draft save, submit, edit |
| `R07_REQUIRED_FIELD` | Data wajib belum lengkap: {fields}. | submit |
| `R07_AGREEMENT_REQUIRED` | Pilih minimal satu kerja sama. | submit |
| `R07_IA_REQUIRED` | Implementation Arrangement (PDF) wajib diunggah. | submit |
| `R07_IR_REQUIRED` | Implementation Report (PDF) wajib diunggah. | submit |
| `R08_END_AFTER_TODAY` | Kegiatan belum selesai. Tanggal selesai harus hari ini atau sebelumnya. | submit, edit_verified_activity |
| `R09_NO_ACADEMIC_YEAR` | Tanggal mulai berada di luar tahun akademik yang terdaftar. Hubungi Admin IO. | submit |
| `R11_PARTICIPANTS_REQUIRED` | Jenis kegiatan ini wajib memiliki data peserta. | submit |
| `R12_OUTBOUND_STUDENT_REQUIRED` | Kegiatan outbound wajib memiliki minimal satu mahasiswa PETRA. | submit |
| `R12_INBOUND_STUDENT_REQUIRED` | Kegiatan inbound wajib memiliki minimal satu mahasiswa inbound. | submit |
| `R13_FILE_TOO_LARGE` | Ukuran berkas melebihi 10 MB. | storage_put |
| `R13_FILE_TYPE` | Format berkas tidak diizinkan ({allowed}). | storage_put, register_activity_file |
| `R14_UNIT_NOT_ALLOWED` | Anda hanya dapat mengajukan kegiatan untuk unit Anda sendiri. | save_activity_draft |
| `R15_NOT_DRAFT` | Hanya draf yang dapat dihapus. | delete_draft |
| `R16_NRP_NOT_FOUND` | NRP tidak ditemukan di data BAAK: {list}. | save_participants, submit |
| `R16_SECTION_MISMATCH` | NRP {nrp} terdaftar sebagai {kategori}; pindahkan ke bagian yang sesuai. | save_participants (inbound_exchange NRP in internal section) |
| `R17_NOT_INBOUND` | NRP {nrp} bukan mahasiswa inbound (kategori inbound_exchange). | save_participants |
| `R17_INBOUND_DATA_REQUIRED` | Mahasiswa inbound {nrp} wajib memiliki institusi asal dan transkrip (PDF). | submit, commit_participant_edit |
| `R19_EMPLOYEE_NOT_FOUND` | ID pegawai tidak ditemukan di data SDM: {list}. | save_participants, submit |
| `R21_NEW_VERSION_REQUIRED` | Perbarui data peserta (versi baru) sebelum mengajukan ulang. | submit (mobility revision without draft version) |
| `R22_DUPLICATE_NRP` | NRP {nrp} tercantum lebih dari sekali. | save_participants |
| `R22_DUPLICATE_EMPLOYEE` | ID pegawai {id} tercantum lebih dari sekali. | save_participants |
| `R26_REASON_REQUIRED` | Pilih alasan penolakan. | partnership_reject |
| `R26_NOTE_REQUIRED` | Catatan penolakan wajib diisi. | partnership_reject |
| `R27_NOTE_REQUIRED` | Catatan revisi wajib diisi. | *_request_revision |
| `R29_EDIT_FORBIDDEN` | Hanya tim IO terkait yang dapat mengubah kegiatan terverifikasi. | edit_verified_activity, commit_participant_edit, file RPCs on verified |
| `R34_UNLINK_ADMIN_ONLY` | Hanya Admin IO yang dapat membatalkan tautan duplikat. | unlink_activity |
| `DUP_SAME_GROUP` | Kedua kegiatan sudah berada dalam satu grup kegiatan. | link_* |
| `R53_ALREADY_MATCHED` | Entri ini sudah dicocokkan dengan kegiatan SIM. | match_known_activity |
| `R54_NO_UNIT` | Entri belum memiliki unit; tentukan unit sebelum mengingatkan. | nudge_known_activity |
| `R54_NUDGE_TOO_SOON` | Pengingat sudah dikirim pada {tanggal}; dapat dikirim ulang setelah {n} hari. | nudge_known_activity |
| `R55_ALREADY_FROZEN` | Snapshot untuk periode ini sudah dibekukan. Gunakan "Bekukan ulang". | freeze_snapshot |
| `R55_NO_SEMESTER` | Kalender semester untuk periode ini belum diatur. | freeze_snapshot, period_info |
| `R58_REASON_REQUIRED` | Alasan pembekuan ulang wajib diisi. | refreeze_snapshot |
| `R58_NOT_LIVE` | Snapshot ini sudah digantikan. | refreeze_snapshot |
| `SETTINGS_INVALID` | Pengaturan {key} tidak valid. | update_settings |
| `CAL_INVALID_RANGE` | Rentang tanggal kalender tidak valid atau tumpang tindih. | upsert_academic_year/semester |
| `FILE_FORBIDDEN` | Anda tidak memiliki akses ke berkas ini. | storage_put/get |
| `FILE_NOT_FOUND` | Berkas tidak ditemukan. | storage_get |

App-only codes (never from SQL): `RATE_LIMITED` (Terlalu banyak permintaan. Coba lagi sebentar.), `INTERNAL` (Terjadi kesalahan pada server.), `BAD_REQUEST` (Permintaan tidak valid.).

---

## 3. RPC catalogue

Notation: **Who** = roles allowed (else `AUTH_FORBIDDEN`). "unit editor" = `_is_unit_editor(activity)`. All mutate RPCs return after writing logs/notifications atomically. Status results use:

```jsonc
// ActivityStatusResult
{ "id": "uuid", "status": "verified", "partnership_status": "approved", "mobility_status": "approved", "verified_at": "…|null" }
```

### 3.1 Lookups

| Signature | Who | Behaviour |
|---|---|---|
| `lookup_students(p_nrps text[]) returns setof mock_baak.students` | any authenticated | Schema §4 (stable, definer). |
| `lookup_employees(p_ids text[]) returns setof mock_hr.employees` | any authenticated | Schema §4. |
| `documents_valid_between(p_start date, p_end date, p_unit_id int default null) returns table(document_id int, doc_number text, title text, kind text, status text, start_date date, end_date date, auto_renewed boolean, is_archived boolean, chain_id int, current_doc_number text, partners jsonb, in_scope boolean)` | any authenticated | R-04: `status not in ('in_process','rejected')`, `start_date <= p_end and (auto_renewed or coalesce(terminated_at::date, end_date) >= p_start)`. `partners` = `[{"partner_id":1,"name":"…","country_code":"JP","country_name":"Jepang","is_lead":true}]`. `in_scope` = `p_unit_id` is null or unit in `document_scope_units`. Ordered by doc_number. |

### 3.2 Submission

**`save_activity_draft(p_id uuid, p_data jsonb) returns uuid`**
- Who: create (`p_id` null): submitter (then `submitter_unit_id` must equal `my_unit()` else `R14_UNIT_NOT_ALLOWED`) or io_admin (any unit). Update: unit editor, and activity `status='draft'` **or** `partnership_status='revision_requested'` (else `STATE_INVALID`).
- `p_data` (`ActivityDetailPayload`, all keys required on create; on update absent keys keep their value):
  ```jsonc
  { "name": "…", "type_id": 7, "start_date": "2026-08-03", "end_date": "2026-08-21",
    "mode": "offline", "venue": "…|null", "city": "…|null", "country_code": "JP|null",
    "sks_recognized": 3|null, "funding_source": "pcu|partner|government|participant|mixed|none|null",
    "description": "…", "submitter_unit_id": 10, "co_unit_ids": [11],
    "document_ids": [101, 102], "sdg_ids": [4, 17],
    "external_persons": [{ "full_name": "…", "institution": "…", "country_code": "JP", "role": "speaker", "notes": null }] }
  ```
- Validates: `name, type_id, start_date, end_date, mode, description, submitter_unit_id` present (`VALIDATION_REQUIRED` with `{"fields":[…]}`); `end_date >= start_date` (`END_BEFORE_START`); type active; each document valid for dates (`R04_AGREEMENT_NOT_VALID`). Does **not** check R-08/R-09 (submit does).
- Effects: create → new `event_groups` row, activity (`submitted_at` null ⇒ draft), `activity_units` (submitter `is_submitter=true` + co-units), docs (`out_of_scope_warning` = submitter unit not in `document_scope_units`), sdgs, external persons (replace-all), log `('revision'…)` **not** written for drafts except one `system/create` log. Update in revision state → replace child sets, and write `_log(id,'revision','partnership','edit_detail', null, diff)` where diff = `{field: [old, new]}` over changed scalar fields and `document_ids`, `co_unit_ids`, `sdg_ids`, `external_persons` (as arrays).

**`delete_draft(p_id uuid) returns void`** — Who: unit editor. `status='draft'` else `R15_NOT_DRAFT`. Hard-deletes the draft and all children incl. its `file_blobs` (R-15).

**`ensure_participant_draft(p_activity uuid) returns jsonb`** → `{"version_id":"uuid","version":2,"created":true}`
- Who/when (participant-edit permission, also used by `activity_detail.permissions.can_edit_participants`):
  unit editor and (`status='draft'` or `mobility_status='revision_requested'` or (`partnership_status='revision_requested'` and `mobility_status='not_required'`)); **or** `in_team('mobility')` and `status='verified'` (post-verification edit, R-29).
- Returns the existing `draft` version if any; else creates version `max+1` (1 if none) with `status='draft'`, copying all student/staff rows (with `row_note` cleared) from the latest version.

**`save_participants(p_activity uuid, p_students jsonb, p_staff jsonb) returns jsonb`**
- Who/when: same as `ensure_participant_draft` (calls it). Replaces **all** rows of the draft version.
- `p_students`: `[{"section":"internal","nrp":"D31240187"}, {"section":"inbound","nrp":"X01260012","home_institution":"…|null","home_student_number":"…|null","home_country_code":"JP|null","transcript_path":"realisasi-transcripts/…|null"}]`; `p_staff`: `[{"employee_id":"PG204517"}]`.
- Validates: duplicates (`R22_DUPLICATE_NRP`, `R22_DUPLICATE_EMPLOYEE`); every NRP in `mock_baak` (`R16_NRP_NOT_FOUND`, detail rows for **all** missing); section/category match: a `regular` NRP in the `inbound` section → `R17_NOT_INBOUND`, an `inbound_exchange` NRP in the `internal` section → `R16_SECTION_MISMATCH`; employees exist (`R19_EMPLOYEE_NOT_FOUND`); a non-null `transcript_path` must be an existing `file_blobs` path under `realisasi-transcripts/<p_activity>/v<draft version>/` (`VALIDATION_INVALID`). Names/faculty/prodi/unit_name are copied **from the registries** (client values ignored); inbound `home_institution`/`home_country_code` default from BAAK when null.
- Returns `{"version_id":"uuid","version":2,"students":14,"staff":1,"warnings":[{"section":"internal","id":"B11220031","status":"graduated"}]}` (R-18 warnings for graduated/inactive students and inactive employees).

**`submission_checklist(p_id uuid) returns jsonb`** — Who: anyone who `can_view_activity`. Runs every submit validation without raising: `[{"code":"R07_IA_REQUIRED","ok":false,"message":"…"}, …]` in fixed order: `R07_REQUIRED_FIELD, R07_AGREEMENT_REQUIRED, R04_AGREEMENT_NOT_VALID, R08_END_AFTER_TODAY, R09_NO_ACADEMIC_YEAR, R07_IA_REQUIRED, R07_IR_REQUIRED, R11_PARTICIPANTS_REQUIRED, R12_OUTBOUND_STUDENT_REQUIRED, R12_INBOUND_STUDENT_REQUIRED, R16_NRP_NOT_FOUND, R17_INBOUND_DATA_REQUIRED, R19_EMPLOYEE_NOT_FOUND, R21_NEW_VERSION_REQUIRED`. Also returns late notice: the last element is `{"code":"LATE_NOTICE","ok":true,"message":"Batas pelaporan 14 Sep 2026 telah lewat — …","late":true}` when `today() > reporting_deadline` (ok stays true; informational).

**`submit_activity(p_id uuid) returns jsonb`** → `ActivityStatusResult & {"is_late":bool,"duplicates_found":int}`
- Who: unit editor. State: `status='draft'` (initial) or any track `revision_requested` (resubmit); else `STATE_INVALID`.
- Validates: the checklist; raises the **first** failing code with `detail={"failures":[…all failing…]}`. R-07 required at submit: `name,type_id,start_date,end_date,mode,description`, plus `venue` always (online = platform name), `city` and `country_code` when mode ≠ online.
- Mobility requirement (R-11): `required = type.requires_mobility_review or draft/latest version has ≥1 row`.
- Initial submit: `submitted_at = now_ts()`; `partnership_status='pending'`; draft version → `pending` (`submitted_by`, `submitted_at`) and `mobility_status='pending'` if required, else delete empty draft version and `mobility_status='not_required'`; log `submit`; notify Partnership team (`submission_received`) and Mobility team if required; `_scan_duplicates`.
- Resubmit: if `partnership_status='revision_requested'` → `pending`, log `resubmit` (track partnership). **R-24**: if `type_id` differs from the value it had when the latest partnership `request_revision` was logged (derive from the earliest `edit_detail` diff of `type_id` after that log), recompute `required`: if required → draft version (or a new copy of the latest version if no draft) → `pending`, `mobility_status='pending'`; else `mobility_status='not_required'` and delete the draft version. If type unchanged but a draft version exists → it becomes `pending` and `mobility_status='pending'`.
  If `mobility_status='revision_requested'` → a draft version must exist (`R21_NEW_VERSION_REQUIRED`) → `pending`, `mobility_status='pending'`, log `resubmit` (track mobility). Both tracks in revision → both handled in one call. Notify the team(s) concerned.
- `submitted_at` is never changed on resubmit (R-10 `is_late` stays from first submit).

`_scan_duplicates(p_activity uuid) returns int` (internal): R-33 candidates against non-draft, non-rejected activities in other event groups sharing ≥1 `chain_id`, `a.start_date <= b.end_date + w and b.start_date <= a.end_date + w`, `similarity(lower(a.name), lower(b.name)) >= dup_name_similarity`; insert `(least(id), greatest(id))` with `score = round(similarity,2)`, `on conflict do nothing`; notify Partnership (`duplicate_candidate`).

### 3.3 Files & storage

Paths: `realisasi-files/<activity_id>/<ia|ir|evidence>/<uuid>.<ext>`; `realisasi-transcripts/<activity_id>/v<version>/<nrp>-<8 hex>.pdf`.

| Signature | Who | Behaviour / errors |
|---|---|---|
| `can_read_file(p_path text) returns boolean` | any | `realisasi-files/…`: `can_view_activity(seg2)` and an `activity_files` row with that `storage_path` exists (viewer: verified only, via can_view_activity). `realisasi-transcripts/…`: `can_view_participants(seg2)`. |
| `storage_put(p_path text, p_mime text, p_data bytea) returns void` | see right | Bucket = first segment (`VALIDATION_INVALID` otherwise); size ≤ 10 485 760 (`R13_FILE_TOO_LARGE`); transcripts: `application/pdf` only; files: `application/pdf`, `image/jpeg`, `image/png` (`R13_FILE_TYPE`); PDF must start with `%PDF-`. Write permission: files → unit editor with `status='draft'` or `partnership_status='revision_requested'`, or (`status='verified'` and `in_team('partnership')`); transcripts → participant-edit permission (§3.2) and `v<version>` equals the current draft version. Else `FILE_FORBIDDEN`. Inserts `file_blobs` (`created_by = auth.uid()`). |
| `storage_get(p_path text) returns table(data bytea, mime text, size_bytes int)` | any | `FILE_FORBIDDEN` if not `can_read_file`; `FILE_NOT_FOUND` if no blob. |
| `register_activity_file(p_activity uuid, p_kind realisasi.file_kind, p_storage_path text, p_filename text, p_size_bytes int, p_mime text) returns jsonb` | same as files write | ia/ir: mime must be `application/pdf` (`R13_FILE_TYPE`); `version = max(version for kind)+1`; previous current → `is_current=false`. evidence: `version=1`, `is_current=true`. Blob at `p_storage_path` must exist. Logs: revision state → `revision/partnership/file_upload` with `{"kind":…,"filename":…,"version":…}`; verified → `update/partnership/file_upload` (in_frozen_period computed). Returns `{"id":12,"kind":"ia","version":2,"storage_path":"…","href":"/api/files/…"}`. |
| `add_evidence_link(p_activity uuid, p_url text, p_label text) returns jsonb` | same | `url` must start with `http://` or `https://` (`VALIDATION_INVALID`); inserts evidence row with `url`, `filename = p_label`. Same return shape (`href` = url). |
| `remove_activity_file(p_file_id bigint) returns void` | same | Evidence only (`STATE_INVALID` for ia/ir — replace by uploading); sets `is_current=false` (no delete). Logged like upload with action `file_remove`. |

### 3.4 Verification

| Signature | Who | Pre-state | Effects |
|---|---|---|---|
| `partnership_approve(p_activity uuid, p_note text default null) returns jsonb` | `in_team('partnership')` | `partnership_status='pending'` (`TRACK_NOT_PENDING`), status ≠ draft/rejected | → `approved`; log `verification/partnership/approve`; if now `verified` notify unit `activity_verified`. |
| `partnership_request_revision(p_activity uuid, p_note text) returns jsonb` | partnership | pending | note required (`R27_NOTE_REQUIRED`); → `revision_requested`; log `verification/partnership/request_revision` with note; notify unit `revision_requested`. |
| `partnership_reject(p_activity uuid, p_reason text, p_note text) returns jsonb` | partnership | pending | `p_reason in ('duplicate','not_partnership','wrong_agreement','other')` (`R26_REASON_REQUIRED`); note required (`R26_NOTE_REQUIRED`); → `rejected`, `rejection_reason = p_reason`; latest pending/draft pset untouched; log `reject`; notify unit `activity_rejected`. |
| `mobility_approve(p_activity uuid, p_note text default null) returns jsonb` | `in_team('mobility')` | `mobility_status='pending'`, status ≠ rejected | latest `pending` version → `approved` (`reviewed_by/at`, `review_note`; trigger supersedes previous approved); track → `approved`; log; notify unit if `verified`. |
| `mobility_request_revision(p_activity uuid, p_note text, p_row_notes jsonb default '[]') returns jsonb` | mobility | pending | note required; `p_row_notes = [{"kind":"student","id":"<nrp>","note":"…"},{"kind":"staff","id":"<employee_id>","note":"…"}]` written to `row_note` of the pending version; version → `revision_requested` (kept read-only forever); track → `revision_requested`; log; notify unit. |
| `edit_verified_activity(p_id uuid, p_data jsonb, p_note text) returns jsonb` | `in_team('partnership')` | `status='verified'` (`STATE_INVALID`) | Partial `ActivityDetailPayload` (`submitter_unit_id` immutable → `VALIDATION_INVALID`); validates like draft save + `R08_END_AFTER_TODAY` + `R09_NO_ACADEMIC_YEAR`; applies; log `update/partnership/edit` with diff + note, `in_frozen_period`. Status/`verified_at` unchanged. Returns `{"diff":{…},"in_frozen_period":bool}`. |
| `commit_participant_edit(p_activity uuid, p_note text) returns jsonb` | `in_team('mobility')` | `status='verified'` and a draft version exists | Validates R-16/R-17/R-19/R-12 on the draft; draft → `approved` (submitted_by = reviewed_by = actor, auto-approved); previous approved → superseded; log `update/mobility/edit` with diff `{"students":{"added":[nrp…],"removed":[nrp…]},"staff":{"added":[…],"removed":[…]}}`. Returns `{"version":3,"diff":{…},"in_frozen_period":bool}`. |

### 3.5 Duplicates

| Signature | Who | Behaviour |
|---|---|---|
| `link_duplicates(p_candidate_id bigint, p_note text default null) returns jsonb` | partnership | Candidate `open` (`STATE_INVALID`); merge: every activity of the group of the **later-created** activity moves to the group of the earlier one; candidate → `linked` (`resolved_by/at`); log `verification/partnership/link_duplicate` on every moved activity and the target; returns `{"event_group_id":"uuid","activity_ids":[…]}`. |
| `link_activities(p_activity_a uuid, p_activity_b uuid, p_note text) returns jsonb` | partnership | Manual link from activity detail; both non-draft non-rejected; `DUP_SAME_GROUP` if already same group; upserts candidate (score = similarity) as `linked`; same merge as above. |
| `dismiss_duplicate(p_candidate_id bigint, p_note text default null) returns void` | partnership | `open` → `dismissed`. |
| `unlink_activity(p_activity uuid, p_note text) returns jsonb` | io_admin (`R34_UNLINK_ADMIN_ONLY` for others) | Activity moves to a new event group; `linked` candidates involving it → `dismissed`; log `update/partnership/unlink_duplicate` (note required, `VALIDATION_REQUIRED`). |

### 3.6 Known activities (R-51..R-54)

| Signature | Who | Behaviour |
|---|---|---|
| `create_known_activity(p_data jsonb) returns bigint` | partnership | `KnownActivityPayload` `{"title","activity_date","unit_id|null","partner_name|null","country_code|null","is_international","source","source_reference|null","notes|null"}`; required `title, activity_date, is_international, source`. |
| `update_known_activity(p_id bigint, p_data jsonb) returns void` | partnership | Same payload, partial. Not allowed when `matched` (`STATE_INVALID`). |
| `known_match_suggestions(p_id bigint) returns jsonb` | `is_io()` | `[{"activity_id","code","name","start_date","end_date","unit_names":[],"status","score":0.62}]` — non-draft, non-rejected activities; `known.unit_id is null or unit in activity_units`; `start_date` within ±`known_match_window_days` of `activity_date`; `similarity ≥ known_name_similarity`; sorted by score desc, max 5. |
| `match_known_activity(p_id bigint, p_activity uuid) returns void` | partnership | `unmatched` → `matched` (`R53_ALREADY_MATCHED` if matched; `STATE_INVALID` if dismissed). |
| `unmatch_known_activity(p_id bigint) returns void` | partnership | `matched` → `unmatched`. |
| `dismiss_known_activity(p_id bigint, p_note text) returns void` | partnership | `unmatched` → `dismissed`; note appended to `notes`. |
| `nudge_known_activity(p_id bigint) returns timestamptz` | partnership | `unmatched` only; `unit_id` required (`R54_NO_UNIT`); `nudged_at` null or older than `nudge_resend_days` (`R54_NUDGE_TOO_SOON`); notifies unit (`known_nudge`, link `/realisasi/kegiatan/baru`); sets and returns `nudged_at = now_ts()`. |

### 3.7 Admin / settings (io_admin only)

| Signature | Behaviour |
|---|---|
| `update_settings(p_values jsonb) returns jsonb` | Keys must be in §2.3 table (`SETTINGS_INVALID`); ints ≥ 0 (`sla_red_days > sla_yellow_days`, `revision_escalate_days > revision_reminder_days`), similarities in (0,1], `demo_today` null or valid date. Upserts with `updated_by`. Returns full `{key: value}` incl. `demo_today`. |
| `upsert_academic_year(p_id int, p_label text, p_start date, p_end date) returns int` | `p_id` null → insert + auto-create semesters: Ganjil `[start, start + 6 months - 1 day]`, Genap `[that+1, end]`, cutoffs `end_date + 30`. No overlap with other years (`CAL_INVALID_RANGE`). Calls `_rederive_periods()`. |
| `upsert_semester(p_id int, p_ay_id int, p_term realisasi.semester_term, p_start date, p_end date, p_cutoff date) returns int` | Inside AY, no overlap, `cutoff >= end` (`CAL_INVALID_RANGE`). Calls `_rederive_periods()`. Existing snapshots unchanged (R-56). |
| `upsert_activity_type(p_id int, p_data jsonb) returns int` | `{"name","direction","counts_as_mobility","counts_for_s1","requires_mobility_review","is_active","sort_order"}`. No delete (deactivate). |
| `upsert_holiday(p_day date, p_name text) returns void` / `delete_holiday(p_day date) returns void` | Holidays are configuration (hard delete allowed). |
| `freeze_snapshot(p_ay int, p_kind realisasi.snapshot_kind, p_as_of timestamptz default null, p_actor uuid default null) returns uuid` | See §4.4. When `auth.uid()` is not null the caller must be io_admin. `p_as_of` null → `now_ts()`; `p_actor` null → `auth.uid()` (null = scheduled job). |
| `refreeze_snapshot(p_snapshot uuid, p_reason text) returns uuid` | See §4.4. |
| `run_daily_jobs() returns jsonb` | See §5.1. When `auth.uid()` is not null the caller must be io_admin. |

### 3.8 Misc

| Signature | Who | Behaviour |
|---|---|---|
| `mark_notifications_read(p_ids bigint[] default null) returns int` | any | Own notifications only; null = all unread; returns count updated. |
| `log_export(p_kind text, p_filters jsonb, p_row_count int, p_contains_personal boolean) returns bigint` | any | Inserts `export_log` with `actor_id = auth.uid()`. Called by every export route (R-63). |

### 3.9 Read RPCs (JSON shapes in §4)

| Signature | Who | Returns |
|---|---|---|
| `period_info(p_ay_id int, p_period text) returns jsonb` | any | `PeriodInfo` (§4.5). `p_period in ('ganjil','full','live')`. |
| `dashboard(p_ay_id int default null, p_period text default 'live', p_unit_id int default null) returns jsonb` | any | `DashboardData`. AY null → AY containing `today()` (else latest). Submitter: `p_unit_id` forced to `my_unit()`. |
| `kpi_drilldown(p_ay_id int, p_period text, p_kpi text, p_bucket text default null, p_unit_id int default null, p_snapshot_id uuid default null) returns jsonb` | any (submitter forced to own unit; viewer/all others free) | `DrilldownResult`. `p_kpi in ('1.1','1.19.S1','1.19.24','1.19.S8','base')`. `p_snapshot_id` overrides ay/period. |
| `kpi_participant_rows(p_ay_id int, p_period text, p_unit_id int default null, p_snapshot_id uuid default null) returns jsonb` | mobility, io_admin; submitter (forced own unit). Others `AUTH_FORBIDDEN` | `[{"activity_id","code","name","direction","event_group_id","section","nrp","full_name","faculty_name","prodi_name","home_institution","home_country_code","start_date","semester_label"}]` — the rows counted in KPI 1.1 for that period/scope (personal data). |
| `activity_detail(p_id uuid) returns jsonb` | `can_view_activity` else `NOT_FOUND` | `ActivityDetail` (§4.7). |
| `participant_version(p_activity uuid, p_version int default null) returns jsonb` | `can_view_participants` else `AUTH_FORBIDDEN` | `ParticipantVersion` (§4.7); null version = latest (including draft only for unit editors / mobility). |
| `participant_counts(p_activity uuid) returns jsonb` | `can_view_activity` | `ParticipantCounts`: `{"version":2,"status":"approved","internal_students":12,"inbound_students":0,"staff":1}` for the approved version, else latest non-draft, else `null`. |
| `nav_counts() returns jsonb` | any | `{"partnership_queue":3,"mobility_queue":2,"duplicates_open":1,"revision_inbox":0,"unread_notifications":4}` — zeros where the role has no access; `revision_inbox` = own-unit activities in `revision_requested` (submitter) . |
| `agreement_realization(p_document_id int) returns jsonb` | any | `AgreementRealization` (§4.8). Non-IO: verified activities only; IO: all non-draft. |
| `agreement_flags(p_ay_id int default null) returns jsonb` | any | `[{"document_id":905,"chain_id":904,"flag":"realized|not_realized|grace|inactive","grace_until":"2026-12-15|null","activities_this_ay":2,"last_activity_date":"2026-05-11|null"}]` for every document (Live semantics of the AY, default current). |
| `snapshot_list(p_ay_id int default null) returns jsonb` | any (submitter: `summary` from own unit) | `SnapshotListRow[]` newest first, superseded included. |
| `snapshot_detail(p_snapshot uuid) returns jsonb` | io roles, viewer | `SnapshotDetail`. |
| `snapshot_late_additions(p_snapshot uuid) returns jsonb` | io roles, viewer | `LateAdditionRow[]`. |
| `snapshot_post_freeze_changes(p_snapshot uuid) returns jsonb` | io roles, viewer | `PostFreezeChangeRow[]`. |

`compute_kpis` and `kpi_items` are **internal** (definer, not granted); only the read RPCs above, `freeze_snapshot` and SQL tests call them.

---

## 4. KPI engine, snapshots, read models

### 4.1 Windows

| Period | from | to (window_end) | cutoff | kind |
|---|---|---|---|---|
| `ganjil` | AY start | Ganjil end | Ganjil cutoff | `ganjil_ytd` |
| `full` | AY start | AY end | Genap cutoff | `genap_full_year` |
| `live` | AY start | `today()` | `today()` | — |

If a **live (non-superseded) snapshot** exists for (AY, kind) the period is *frozen* and reads come from the snapshot. Otherwise compute live with `to = least(window_end, today())`, `cutoff = least(cutoff, today())`, `as_of = null`.
KPI 1.1 / S1 / S8 / base use `[from, to]`; KPI 1.19.24 uses `[from, cutoff]` for both "active" and numerator (R-43/R-44 literal).

### 4.2 `kpi_items`

```sql
realisasi.kpi_items(p_from date, p_to date, p_cutoff date, p_ay_id int,
                    p_as_of timestamptz default null, p_unit_id int default null)
returns table(kpi_code text, bucket text, ref_type text, ref_id text, activity_id uuid)
```
Common filter for activities: `status='verified' and verified_at <= coalesce(p_as_of, now_ts())`; unit scope (`p_unit_id` not null) = `exists activity_units(unit_id = p_unit_id)`. `activity_id` is the activity that produced the row (null for chain/known rows except realized chains: null).

| kpi_code | bucket | ref_type | ref_id | Rule |
|---|---|---|---|---|
| `1.1` | `outbound` / `inbound` | `participant` | `<activity_id>:<nrp>` | R-38. University: one row per distinct `(nrp, event_group_id)`; `activity_id` = representative = earliest `verified_at` (tie: smallest `code`) activity in that group containing the NRP. Unit: one row per distinct `(nrp, activity_id)`. Approved version only; outbound = `internal` section of `outbound` types with `counts_as_mobility`; inbound = `inbound` section of `inbound` types with `counts_as_mobility`. |
| `1.19.S1` | `international` / `domestic` | `activity` | activity uuid | `counts_for_s1` types. University: one row per event group (representative = earliest verified, tie smallest code); unit: one row per activity. International = any partner snapshot with `country_code <> 'ID'`. |
| `1.19.24` | `denominator` | `chain` | chain_id | R-42/R-43: chains active in `[p_from, p_cutoff]` (`chain_start <= p_cutoff and (auto_renewed or chain_end >= p_from)`) and not in grace. Unit: chains with any document in `document_scope_units(unit_id = p_unit_id)`. |
| `1.19.24` | `numerator` | `chain` | chain_id | denominator chains with ≥1 qualifying activity (`start_date between p_from and p_cutoff`) linked via `activity_documents.chain_id`; unit: activity of that unit. |
| `1.19.24` | `grace_excluded` | `chain` | chain_id | active chains with `not auto_renewed and chain_start > p_cutoff - grace_period_months`. |
| `1.19.S8` | `reported` | `activity` | activity uuid | R-48: international verified activities (any type), one per event group (unit: per activity). |
| `1.19.S8` | `unmatched_known` | `known_activity` | id | R-49: `status='unmatched' and is_international and activity_date between p_from and p_to and created_at <= as_of`; unit: `unit_id = p_unit_id`. |
| `base` | `verified_activity` | `activity` | activity uuid | every qualifying verified activity with `start_date between p_from and p_to` (unit-scoped when unit). |

Schema §5.2 wrappers stay with their original signatures and are thin `select … from kpi_items(…)` aggregations with `p_ay_id => null` (`kpi_1_19_24` reads `p_grace_months` instead of the setting; implement via an internal `_kpi_items(…, p_grace_months int)` that `kpi_items` calls with the setting).

### 4.3 `compute_kpis` → `KpiValues`

```sql
realisasi.compute_kpis(p_from date, p_to date, p_cutoff date, p_ay_id int,
                       p_as_of timestamptz default null, p_unit_id int default null) returns jsonb
```
Counts are derived **only** from `kpi_items` (so values and items always agree). `pct` = `round(100.0 * n / nullif(d,0), 1)` (JSON number or `null`).

```jsonc
{
  "params": { "from": "2026-08-01", "to": "2026-10-01", "cutoff": "2026-10-01", "ay_id": 2,
              "as_of": "2026-10-01T09:00:00+07:00", "unit_id": null, "grace_period_months": 6 },
  "kpi_1_1": {
    "inbound": 4, "outbound": 30, "total": 34,
    "by_semester": [ { "semester_id": 3, "term": "ganjil", "label": "Ganjil 2026/2027", "inbound": 4, "outbound": 30 } ]
  },                                    // by_semester: every semester of the AY overlapping [from,to], by activity start_date
  "kpi_1_19_s1": { "international": 9, "domestic": 2 },
  "kpi_1_19_24": {
    "all":           { "numerator": 12, "denominator": 30, "grace_excluded": 2, "pct": 40.0 },
    "international": { "numerator": 9,  "denominator": 21, "grace_excluded": 2, "pct": 42.9 },
    "domestic":      { "numerator": 3,  "denominator": 9,  "grace_excluded": 0, "pct": 33.3 }
  },
  "kpi_1_19_s8": { "reported": 9, "unmatched_known": 2, "pct": 81.8 },
  "charts": {
    "mobility_by_semester": [ /* identical to kpi_1_1.by_semester */ ],
    "by_country":   [ { "country_code": "JP", "country_name": "Jepang", "activities": 3 } ],     // top 10 desc; partner-snapshot countries incl. ID; univ: distinct event groups of base, unit: distinct activities
    "by_unit":      [ { "unit_id": 10, "unit_name": "Fakultas Teknologi Industri", "activities": 4 } ], // univ only (activity_units incl. co-units, distinct activities); [] at unit level
    "by_sdg":       [ { "sdg_id": 1, "name": "Tanpa Kemiskinan", "activities": 0 } ],            // always 17 entries
    "realization_by_unit": [ { "unit_id": 10, "unit_name": "…", "numerator": 3, "denominator": 5, "pct": 60.0 } ], // univ only, from by_unit[].kpi_1_19_24.all; [] at unit level
    "top_partners": [ { "partner_id": 1, "partner_name": "…", "country_code": "JP", "activities": 3 } ]  // top 10
  },
  "by_unit": [                          // present only when p_unit_id is null
    { "unit_id": 10, "unit_name": "Fakultas Teknologi Industri",
      "kpi_1_1": { …same shape… }, "kpi_1_19_s1": { … }, "kpi_1_19_24": { "all": …, "international": …, "domestic": … },
      "kpi_1_19_s8": { … },
      "charts": { "mobility_by_semester": […], "by_country": […], "by_unit": [], "by_sdg": […], "realization_by_unit": [], "top_partners": […] } }
  ]                                     // every unit appearing in activity_units of a base activity or in document_scope_units of an active chain; = compute_kpis(…, p_unit_id => unit) minus params/by_unit; ordered by unit name
}
```

### 4.4 Snapshots

**`freeze_snapshot(p_ay, p_kind, p_as_of, p_actor) returns uuid`**
1. Window from §4.1 for the kind (semester rows must exist: `R55_NO_SEMESTER`); live snapshot for (AY, kind) must not exist (`R55_ALREADY_FROZEN`).
2. `values = compute_kpis(from, window_end, cutoff, ay, as_of, null)`; `settings_used = settings_json()`; insert `kpi_snapshots` (`frozen_at = as_of`, `frozen_by = p_actor`).
3. Insert every `kpi_items(…)` row into `kpi_snapshot_items` (university level only; `base` included).
4. `is_late_addition` (R-57): let **P** = the live snapshot with the greatest `frozen_at < as_of` (any AY, excluding self). For items whose producing activity (`activity_id`, or for `1.19.24` numerator any realizing activity) has `verified_at > P.frozen_at` and `start_date between P.window_start and P.window_end` → `true`. For a chain in `numerator`, late only if the chain is not in P's `numerator` items.
5. Notify io_admins and viewers (`snapshot_frozen`, link `/realisasi/laporan?report=arsip&snapshot=<id>`).

**`refreeze_snapshot(p_snapshot uuid, p_reason text) returns uuid`** — io_admin; reason required (`R58_REASON_REQUIRED`); target must be live (`R58_NOT_LIVE`). Inside one transaction (deferred FK): mark old `superseded_by = <new id>` first, then insert the new snapshot computed exactly like `freeze_snapshot` with `as_of = now_ts()`, `refreeze_reason = p_reason`, `frozen_by = auth.uid()`. Old snapshot and items are never modified otherwise (R-58/R-59).

**`snapshot_late_additions(p_snapshot) → LateAdditionRow[]`**: (a) activities behind items of this snapshot with `is_late_addition` → `counted_in_this_snapshot = true`; (b) activities with `verified_at in (P.frozen_at, S.frozen_at]` dated within P's window but outside S's window → `false` (e.g. Genap-period late activities listed in next year's Ganjil report).
```jsonc
{ "activity_id": "…", "code": "RL-2026-0019", "name": "…", "unit_names": ["…"], "start_date": "2025-11-10",
  "verified_at": "2026-04-15T10:00:00+07:00", "previous_snapshot_id": "…", "previous_snapshot_label": "Ganjil 2025/2026 (YTD)",
  "counted_in_this_snapshot": true, "kpi_codes": ["1.19.S1","1.19.S8","base"] }
```

**`snapshot_post_freeze_changes(p_snapshot) → PostFreezeChangeRow[]`**: `activity_log` rows with `in_frozen_period` and `created_at > P.frozen_at and created_at <= S.frozen_at` (P as above; no P → `created_at <= S.frozen_at`).
```jsonc
{ "log_id": 77, "activity_id": "…", "code": "…", "name": "…", "kind": "update", "track": "partnership", "action": "edit",
  "actor_name": "IO Partnership", "note": "…", "diff": { "venue": ["A", "B"] }, "created_at": "…" }
```

**`snapshot_list` → `SnapshotListRow`**
```jsonc
{ "id": "…", "ay_id": 1, "ay_label": "2025/2026", "kind": "ganjil_ytd", "label": "Ganjil 2025/2026 (YTD)",
  "window_start": "2025-08-01", "window_end": "2026-01-31", "cutoff_date": "2026-03-02",
  "frozen_at": "…", "frozen_by_name": "Kepala IO | Job terjadwal", "is_live": true,
  "superseded_by": null, "refreeze_reason": null,
  "summary": { "kpi_1_1_total": 40, "kpi_1_19_s1_international": 7, "kpi_1_19_24_pct": 41.2, "kpi_1_19_s8_pct": 100.0 },
  "late_additions": 0, "post_freeze_changes": 0 }
```
**`snapshot_detail` → `SnapshotDetail`**: `{ "snapshot": SnapshotListRow, "values": KpiValues, "settings_used": {…}, "late_additions": LateAdditionRow[], "post_freeze_changes": PostFreezeChangeRow[] }`.

### 4.5 `PeriodInfo`

```jsonc
{ "ay_id": 2, "ay_label": "2026/2027", "period": "live", "kind": null,      // kind: 'ganjil_ytd'|'genap_full_year'|null
  "label": "Live 2026/2027",                                               // 'Ganjil 2026/2027 (YTD)' | 'Setahun 2026/2027' | 'Live 2026/2027'
  "window_start": "2026-08-01", "window_end": "2026-10-01", "cutoff": "2026-10-01",
  "frozen": false, "snapshot_id": null, "frozen_at": null, "frozen_by_name": null,
  "today": "2026-10-01",
  "academic_years": [ { "id": 1, "label": "2025/2026" }, { "id": 2, "label": "2026/2027" } ] }
```

### 4.6 `DashboardData` and drill-down

```jsonc
// dashboard()
{ "period": PeriodInfo,
  "scope": { "level": "university|unit", "unit_id": null, "unit_name": null },
  "values": KpiValues,                  // frozen+unit → snapshot values.by_unit entry (zeros if absent) with "params" copied; frozen+univ → snapshot values; else compute_kpis
  "previous": { "ay_label": "2025/2026", "kpi_1_1": { "total": 20, "inbound": 2, "outbound": 18 },
                "kpi_1_19_s1": { "international": 5 }, "kpi_1_19_24": { "pct": 35.0 }, "kpi_1_19_s8": { "pct": 100.0 } } | null,
                // same period of the previous AY (snapshot if frozen, else live semantics shifted by 1 year)
  "late_additions": 1,                  // live: verified activities in the window with is_late_addition(); frozen: count of snapshot_late_additions
  "drafts_near_deadline": [ { "id": "…", "code": "…", "name": "…", "end_date": "…", "reporting_deadline": "…", "days_left": -18 } ]
                                        // unit scope only: own-unit drafts with deadline ≤ today()+14, ascending; [] for university
}
// kpi_drilldown()
{ "period": PeriodInfo, "scope": {…}, "kpi": "1.19.24", "bucket": "grace_excluded|null", "rows": [ … ] }
```
Row shapes by `p_kpi` (`rows` sorted by start date / chain start):
- `1.1`, `1.19.S1`, `base`, and the `reported` rows of `1.19.S8` → `ActivityKpiRow`:
  `{ "row_type":"activity", "activity_id","code","name","type_name","direction","unit_names":[],"partner_names":[],"country_codes":[],"start_date","semester_label","event_group_id","linked_count", "bucket":"outbound|inbound|international|domestic|reported|verified_activity", "students": 12 /* 1.1 only: rows of this activity in the KPI, else null */, "is_late_addition": false }`
  For `1.1`, one row per (activity, bucket) aggregated from participant items (no personal data).
- `1.19.24` → `ChainKpiRow`:
  `{ "row_type":"chain", "chain_id","current_document_id","current_doc_number","doc_numbers":[],"kind","title","partner_names":[],"country_codes":[],"is_international","chain_start","chain_end","auto_renewed", "bucket":"realized|not_realized|grace_excluded", "grace_until":"YYYY-MM-DD|null", "activities":[{"id","code","name","start_date","original_doc_number"}], "is_late_addition": false }`
  `p_bucket`: `numerator` → realized; `denominator` → realized + not_realized; `not_realized`; `grace_excluded`; null → all.
- `1.19.S8` `unmatched_known` rows → `{ "row_type":"known", "known_id","title","activity_date","unit_name","partner_name","country_code","source","source_reference" }`.
- Frozen + unit scope: rows derive from the snapshot's `base` items filtered to the unit's activities, re-evaluated against current data (documented mockup limitation; card numbers still come from `values.by_unit`).

### 4.7 `ActivityDetail`, `ParticipantVersion`

```jsonc
// activity_detail()
{ "id","code","name",
  "type": { "id","name","direction","counts_as_mobility","counts_for_s1","requires_mobility_review" },
  "start_date","end_date","duration_days",
  "academic_year": { "id","label" } | null, "semester": { "id","term","label" } | null,
  "mode","venue","city","country_code","country_name","sks_recognized","funding_source","description",
  "submitter_unit": { "id","name" }, "units": [ { "id","name","is_submitter" } ],
  "status","partnership_status","mobility_status","partnership_since","mobility_since",
  "submitted_at","verified_at","rejection_reason","reporting_deadline","is_late",
  "event_group_id", "linked_activities": [ { "id","code","name","unit_name","status" } ],
  "documents": [ { "original_document_id","original_doc_number","current_document_id","current_doc_number","kind","title",
                   "chain_id","start_date","end_date","is_archived","out_of_scope_warning",
                   "partners": [ { "partner_id","name","country_code","country_name" } ] } ],
  "partners": [ { "document_id","partner_id","partner_name","country_code","country_name" } ],   // the snapshot (R-06)
  "is_international": true,
  "sdg_ids": [4, 17],
  "external_persons": [ { "id","full_name","institution","country_code","role","notes" } ],
  "files": [ { "id","kind","version","storage_path","url","filename","size_bytes","mime","is_current","uploaded_by_name","uploaded_at","href" } ],
  "participants": { "can_view_rows": true, "counts": ParticipantCounts | null,
                    "versions": [ { "id","version","status","submitted_at","submitted_by_name","reviewed_at","reviewed_by_name","review_note",
                                    "internal_students","inbound_students","staff" } ] },   // draft versions only listed for unit editors / mobility
  "sla": { "partnership": { "days": 4, "level": "yellow" } | null, "mobility": { … } | null },
  "revision": { "partnership": { "note","requested_by_name","requested_at" } | null, "mobility": { … } | null },
  "rejection": { "reason","note","rejected_by_name","rejected_at" } | null,
  "log": [ { "id","kind","track","action","actor_name","note","diff","in_frozen_period","created_at" } ],   // [] for viewer
  "duplicates": [ { "candidate_id","other_activity_id","other_code","other_name","score","status" } ],      // [] for non-IO
  "flags": { "late": false, "out_of_scope": false, "duplicate_open": false, "late_addition": false },
  "checklist": [ …submission_checklist… ] | null,      // only when permissions.can_submit
  "permissions": ActivityPermissions }

// ActivityPermissions (booleans)
{ "can_edit_draft":        "unit editor && status=draft",
  "can_delete_draft":      "unit editor && status=draft",
  "can_edit_detail":       "unit editor && (status=draft || partnership_status=revision_requested)",
  "can_edit_files":        "same as can_edit_detail",
  "can_edit_participants": "participant-edit permission for the unit (see ensure_participant_draft), excluding the IO post-verification case",
  "can_submit":            "unit editor && (status=draft || any track=revision_requested)",
  "can_partnership_verify":"in_team(partnership) && partnership_status=pending && status not in (draft,rejected)",
  "can_reject":            "same as can_partnership_verify",
  "can_mobility_verify":   "in_team(mobility) && mobility_status=pending && status<>rejected",
  "can_edit_verified_detail":       "status=verified && in_team(partnership)",
  "can_edit_verified_participants": "status=verified && in_team(mobility)",
  "can_link_duplicate":    "in_team(partnership) && status not in (draft,rejected)",
  "can_unlink_duplicate":  "io_admin && linked_count>0",
  "can_view_participants": "can_view_participants(id)",
  "can_view_log":          "role<>viewer" }

// participant_version()
{ "id","activity_id","version","status","submitted_at","submitted_by_name","reviewed_at","reviewed_by_name","review_note",
  "students": [ { "id","section","nrp","full_name","faculty_name","prodi_name","home_institution","home_student_number",
                  "home_country_code","transcript_path","transcript_href","row_note","registry_status":"active|graduated|inactive" } ],
  "staff":    [ { "id","employee_id","full_name","unit_name","row_note","registry_status":"active|inactive" } ] }
```

### 4.8 `AgreementRealization`

```jsonc
{ "document": { "id": 905, "doc_number": "…", "title": "…", "kind": "MoU", "status": "active", "start_date","end_date","auto_renewed" },
  "chain": { "chain_id": 904, "chain_start","chain_end","auto_renewed","is_international",
             "documents": [ { "id","doc_number","kind","status","start_date","end_date","predecessor_id" } ] },   // oldest first
  "current_ay": { "id": 2, "label": "2026/2027" },
  "summary": { "total_activities": 2, "activities_this_ay": 0, "students_inbound": 0, "students_outbound": 0, "last_activity_date": "2026-05-11" },
  "grace": { "in_grace": false, "grace_until": null },
  "activities": [ { "id","code","name","type_name","start_date","end_date","status","unit_names":[],"original_doc_number","current_doc_number" } ] }
```
Students = approved-version counts (outbound internal / inbound inbound) over verified activities on the chain, deduped per (nrp, event group).

---

## 5. Jobs, notifications, seed fixtures

### 5.1 `run_daily_jobs()` → `{"today","sla_notices","revision_reminders","revision_escalations","deadline_reminders","frozen":[{"snapshot_id","ay_label","kind"}]}`

All "once" semantics via `insert into job_marks(key) … on conflict do nothing` (act only when inserted).

| Step | Condition | Mark key | Notify |
|---|---|---|---|
| SLA | track `pending`, level `yellow` / `red` (R-60) | `sla:<activity>:<track>:<level>:<epoch of x_since>` | yellow → team members of the track (`sla_yellow`); red → team + io_admins (`sla_red`) |
| Revision reminder | track `revision_requested`, `today() - x_since::date >= revision_reminder_days` | `rev_remind:<activity>:<track>:<epoch>` | unit (`revision_reminder`) |
| Revision escalation | same, `>= revision_escalate_days` | `rev_escalate:<activity>:<track>:<epoch>` | io_admins + track team (`revision_escalation`) |
| Deadline | drafts: `today() >= deadline - deadline_reminder_before_days` → `h7`; `today() >= deadline` → `h0`; `n = (today()-deadline)/7 >= 1` → `w<n>` | `deadline:<activity>:<tag>` | unit (`deadline_h7` / `deadline_h0` / `deadline_weekly`) |
| Freeze | semesters with `cutoff_date <= today()` and no live snapshot for (AY, kind) — Ganjil → `ganjil_ytd`, Genap → `genap_full_year` | — | via `freeze_snapshot(ay, kind, least(now_ts(), (cutoff_date + time '01:00') at time zone 'Asia/Jakarta'), null)` |

### 5.2 Notification kinds & links (`notifications.kind`, `link`)

| kind | Recipient | Title (ID) | link |
|---|---|---|---|
| `submission_received` | partnership (+ mobility) team | Pengajuan baru: {code} | `/realisasi/verifikasi/kemitraan` (`/mobilitas`) |
| `revision_requested` | unit | Perlu revisi: {code} | `/realisasi/kegiatan/{id}/revisi` |
| `revision_reminder` / `revision_escalation` | unit / IO | Pengingat revisi / Eskalasi revisi: {code} | `/realisasi/kegiatan/{id}` |
| `activity_verified` / `activity_rejected` | unit | Kegiatan terverifikasi / ditolak: {code} | `/realisasi/kegiatan/{id}` |
| `sla_yellow` / `sla_red` | team / team + admin | SLA {n} hari: {code} | queue of the track |
| `deadline_h7` / `deadline_h0` / `deadline_weekly` | unit | Batas pelaporan {date}: {code} | `/realisasi/kegiatan/baru?draft={id}` |
| `duplicate_candidate` | partnership | Kemungkinan duplikat: {code} | `/realisasi/verifikasi/duplikat` |
| `known_nudge` | unit | Mohon laporkan: {title} | `/realisasi/kegiatan/baru` |
| `snapshot_frozen` | io_admin, viewers | Snapshot dibekukan: {label} | `/realisasi/laporan?report=arsip&snapshot={id}` |

### 5.3 Seed fixtures (fixed ids other WPs and tests rely on)

**Profiles** (`public.profiles`, password-less; team membership in `realisasi.team_members`):

| id | email | display_name | app_role | unit_id | teams |
|---|---|---|---|---|---|
| `00000000-0000-4000-8000-000000000001` | kepala.io@demo.petra.ac.id | Kepala IO | io_admin | 2 | partnership, mobility |
| `00000000-0000-4000-8000-000000000002` | io.partnership@demo.petra.ac.id | IO Partnership | io_staff | 2 | partnership |
| `00000000-0000-4000-8000-000000000003` | io.mobility@demo.petra.ac.id | IO Mobility | io_staff | 2 | mobility |
| `00000000-0000-4000-8000-000000000004` | ua-fti@demo.petra.ac.id | UA Fakultas Teknologi Industri | submitter | 10 | — |
| `00000000-0000-4000-8000-000000000005` | ua-fbe@demo.petra.ac.id | UA Fakultas Bisnis & Ekonomi | submitter | 20 | — |
| `00000000-0000-4000-8000-000000000006` | kaprodi-informatika@demo.petra.ac.id | Kaprodi Informatika | submitter | 11 | — |
| `00000000-0000-4000-8000-000000000007` | ua-fsd@demo.petra.ac.id | UA Fakultas Seni & Desain | submitter | 30 | — |
| `00000000-0000-4000-8000-000000000008` | rektorat@demo.petra.ac.id | Rektorat | viewer | 1 | — |

Login page order = this table order.

**Units:** 1 Rektorat (up), 2 International Office (up), 10 Fakultas Teknologi Industri (faculty), 11 Prodi Informatika (prodi, parent 10), 12 Prodi Teknik Elektro (prodi, parent 10), 20 Fakultas Bisnis & Ekonomi (faculty), 21 Prodi Manajemen (prodi, parent 20), 30 Fakultas Seni & Desain (faculty), 31 Prodi Desain Komunikasi Visual (prodi, parent 30); WP-DB may add more ≥ 40. Unit scope is exact-match (no hierarchy roll-up).

**Calendar:** AY 1 = 2025/2026 (2025-08-01 → 2026-07-31), AY 2 = 2026/2027 (2026-08-01 → 2027-07-31). Semesters: 1 Ganjil 25/26 (2025-08-01 → 2026-01-31, cutoff 2026-03-02), 2 Genap 25/26 (2026-02-01 → 2026-07-31, cutoff 2026-08-30), 3 Ganjil 26/27 (2026-08-01 → 2027-01-31, cutoff 2027-03-02), 4 Genap 26/27 (2027-02-01 → 2027-07-31, cutoff 2027-08-30).

**Activity types** (ids in Schema §7.3 order): 1 Student Outbound Mobility, 2 Student Inbound Mobility, 3 Staff Outbound Mobility, 4 Visiting Lecturer / Guest Lecture, 5 Joint Research, 6 Joint Seminar / Conference, 7 Summer / Winter Program (Outbound), 8 Community Service (Joint), 9 Joint Publication.

**NRP faculty letters (mockup):** A FTSP, B FTI (B11 Informatika, B12 Teknik Elektro), C FSD (C21 DKV), D FBE (D31 Manajemen, D32 Akuntansi), E FHIK, F FKIP, G Kedokteran, H Pascasarjana. `D31240187` must exist (regular, active). One NRP `X01260012` inbound_exchange. Unknown-NRP test value: `Z99999999` (must **not** exist). At least one graduated (`B11200005`) and one inactive regular NRP for warnings.

**Special documents** (others: ids 101–199, WP-DB's choice; every scenario doc has ≥1 partner and ≥1 scope unit):

| id | Purpose | Data |
|---|---|---|
| 901 | Grace-excluded in **Live** 2026/2027 | MoU, active, international, start 2026-06-15, end 2031-06-14, no activity, scope FTI |
| 902 | AT-05 grace in Ganjil 2026/2027 | MoA, active, international, start 2026-12-02, end 2029-12-01, no activity |
| 903 | AT-06 auto-renewed w/o activity | MoU, active, `auto_renewed=true`, start 2020-01-15, end 2022-01-14, domestic or intl, no activity |
| 904 | AT-07 chain root (renewed mid-year) | MoU, `status='archived'`, `archived_reason='renewed'`, 2023-09-01 → 2026-03-31, Japan partner, scope FTI |
| 905 | AT-07 renewal | MoU, active, `predecessor_id=904`, 2026-04-01 → 2031-03-31, same partner |
| 906 | never selectable | `status='in_process'` |
| 907 | never selectable | `status='rejected'` |

**Activities** (`id = 'a0000000-0000-4000-8000-0000000000NN'`, `code = 'RL-2026-00NN'`, event group `e0000000-0000-4000-8000-0000000000NN` unless stated):

| NN | Scenario | Unit | Type | Dates | State / notes |
|---|---|---|---|---|---|
| 01–12 | S-01…S-12 baseline | mixed (no FTI/Informatika outbound-mobility types in Ganjil 26/27) | mixed incl. ≥2 inbound (type 2) with inbound students | 01–06 in AY 25/26 (3 Ganjil, 3 Genap), 07–08 Genap 25/26, 09–12 Ganjil 26/27 (Aug–Sep 2026) | verified; ≥6 partner countries + ≥2 domestic; S-05 (Ganjil 25/26) has an `update/partnership/edit` log dated 2026-05-10 with `in_frozen_period=true` |
| 13 | S-13 | 10 FTI | 7 | 2026-08-03 → 2026-08-21 | verified 2026-09-10; 12 internal students (same 12 as S-14); event group `…13` |
| 14 | S-14 | 11 Informatika | 7 | 2026-08-03 → 2026-08-21 | verified 2026-09-12; **event group `…13`**; duplicate_candidates row (13,14) `linked` |
| 15 | S-15a | 20 FBE | 1 | 2026-02-10 → 2026-03-20 | verified; includes D31240187 |
| 31 | S-15b | 20 FBE | 1 | 2026-05-04 → 2026-06-12 | verified; includes D31240187; own event group |
| 16 | S-16 | 10 FTI | 1 | 2026-08-24 → 2026-09-04 | P approved; M `revision_requested` since `today()-15d` (v1 `revision_requested`, 3 students, one row_note) |
| 17 | S-17 | 20 FBE | 6 | 2026-09-07 → 2026-09-08 | P `revision_requested` (note "IA yang diunggah salah"), since `today()-8d`; M `not_required`; no participants |
| 18 | S-18 | 11 Informatika | 7 | 2026-08-03 → 2026-08-20 | rejected, reason `duplicate` |
| 19 | S-19 | 30 FSD | 4 | 2025-11-10 → 2025-11-14 | submitted 2026-03-20 (late), verified **2026-04-15**; international |
| 20 | S-20 | 10 FTI | 5 | 2025-10-06 → 2025-10-10 | verified; linked to doc **904** |
| 32 | S-20b | 10 FTI | 5 | 2026-05-11 → 2026-05-15 | verified; linked to doc **905** |
| 21 | S-21 | 30 FSD | 6 | Genap 25/26 | verified; two documents with partners in two countries |
| 22 | S-22 | 20 FBE | 8 | Ganjil 26/27 | verified; `out_of_scope_warning=true` |
| 23 | S-23 | 30 FSD | 4 | ends 2026-08-14 | **draft**, deadline 2026-09-13 passed |
| 24 | S-24 | 10 FTI | 6 | 2026-06-22 → 2026-07-01 | submitted 2026-08-20 (`is_late`), verified 2026-08-28 |
| 25 | S-25 | 21 Manajemen | 6 | Sep 2026 | P pending since 1 business day (ok) |
| 26 | S-26 | 31 DKV | 4 | Sep 2026 | P pending since 4 business days (yellow) |
| 27 | S-27 | 12 Elektro | 5 | Aug 2026 | P pending since 7 business days (red) |
| 28 | S-28 | 20 FBE | 3 | Sep 2026 | P approved; M pending since 4 business days (yellow) |
| 29 | S-29 | 30 FSD | 2 | Aug 2026 | P approved; M pending since 8 business days (red) |
| 30 | S-30 | 21 Manajemen | 3 | Sep 2026 | P and M pending since 2 business days (ok) |

"since N business days" = `x_since` set to the start (08:00 WIB) of the date N business days before `realisasi.today()` at seed time (helper `realisasi._business_days_ago(n int) returns date` may be added in seed). All seeded activities have IA + IR files (except the draft S-23 which has only IA).

**Known activities** (ids 1–8, all dated 2026-08-01 … 2026-09-30, `created_at` before 2026-10-01): 1–5 `matched` to verified Ganjil 26/27 activities (13, 09, 10, 11, 12); 6–7 `unmatched`, `is_international=true`, units 20 and 30; 8 `dismissed`.

**Snapshots** (from `90_freeze.sql`): AY 1 `ganjil_ytd` frozen_at 2026-03-02 01:00+07 (excludes S-19), AY 1 `genap_full_year` frozen_at 2026-08-30 01:00+07 (S-19 items `is_late_addition=true`; S-05 edit listed as post-freeze change). AY 2: none.

---

## 6. TypeScript

### 6.1 Packages & scripts (`package.json`, FOUNDATION)

`"type"` not set (CommonJS default for configs; use `.mjs`/`.ts` configs). Node ≥ 20.

dependencies: `next@~15.5.0`, `react@^19.0.0`, `react-dom@^19.0.0`, `postgres@^3.4.5`, `zod@^3.24.0`, `react-hook-form@^7.54.0`, `@hookform/resolvers@^3.9.0`, `recharts@^2.15.0`, `exceljs@^4.4.0`, `clsx@^2.1.1`, `tailwind-merge@^2.6.0`, `class-variance-authority@^0.7.1`, `lucide-react@^0.468.0`, `cmdk@^1.0.4`, `sonner@^1.7.0`, `@radix-ui/react-dialog`, `@radix-ui/react-dropdown-menu`, `@radix-ui/react-popover`, `@radix-ui/react-tabs`, `@radix-ui/react-tooltip`, `@radix-ui/react-checkbox`, `@radix-ui/react-switch`, `@radix-ui/react-label`, `@radix-ui/react-slot`, `@radix-ui/react-select`, `@radix-ui/react-collapsible`, `@radix-ui/react-separator`, `@radix-ui/react-radio-group`, `@radix-ui/react-alert-dialog`.
devDependencies: `typescript@^5.7.0`, `@types/node@^20`, `@types/react@^19`, `@types/react-dom@^19`, `tailwindcss@^3.4.17`, `postcss@^8`, `autoprefixer@^10`, `tailwindcss-animate@^1.0.7`, `eslint@^9`, `eslint-config-next@~15.5.0`, `@eslint/eslintrc@^3`, `vitest@^2.1.0`, `@playwright/test@^1.49.0`.
`"overrides": { "react-is": "^19.0.0" }`.

scripts: `dev` (`next dev -p 3000`), `build`, `start`, `lint` (`next lint` or `eslint .`), `typecheck` (`tsc --noEmit`), `test` (`vitest run`), `test:db` (`bash scripts/db-test.sh`), `test:e2e` (`playwright test`), `db:reset` (`bash scripts/db-reset.sh`).

`tsconfig.json`: `strict: true`, `noUncheckedIndexedAccess: true`, path alias `@/*` → `./*`. `next.config.ts`: `serverExternalPackages: ['postgres', 'exceljs']`, `experimental.serverActions.bodySizeLimit = '12mb'`. `.env.example`: `DATABASE_URL=postgresql://postgres@localhost:54322/sim_realisasi`. All modules that touch the DB are server-only (`import 'server-only'` is **not** used; instead never import `lib/db.ts` from client components) and route handlers declare `export const runtime = 'nodejs'`.

### 6.2 `lib/db.ts` (FOUNDATION)

```ts
import postgres from 'postgres';
export type Tx = postgres.TransactionSql;          // what callbacks receive
export const sql: postgres.Sql;                    // singleton (cached on globalThis in dev), max 10 connections
// parsers: 1082 date → 'YYYY-MM-DD' string; 1114/1184 timestamp(tz) → ISO-8601 string; 20 int8 & 1700 numeric → number; 3802/114 json(b) → parsed (default)
export async function withUser<T>(profileId: string, fn: (tx: Tx) => Promise<T>): Promise<T>;
//   sql.begin(async tx => {
//     await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: profileId, role: 'authenticated' })}, true),
//                     set_config('request.jwt.claim.sub', ${profileId}, true)`;
//     await tx`set local role authenticated`;
//     return fn(tx); })
export async function withSystem<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;  // sql.begin without role switch; ONLY for login list + session profile load + getToday()
```

### 6.3 `lib/session.ts` (FOUNDATION)

```ts
export type Role = 'submitter' | 'io_staff' | 'io_admin' | 'viewer';
export type Team = 'partnership' | 'mobility';
export const SESSION_COOKIE = 'demo_uid';
export interface SessionUser { id: string; email: string; displayName: string; role: Role; unitId: number | null; unitName: string | null; teams: Team[]; }
export interface DemoAccount extends SessionUser {}
export async function listDemoAccounts(): Promise<DemoAccount[]>;        // withSystem; order = §5.3
export const getSessionUser: () => Promise<SessionUser | null>;          // React cache(); reads cookie, loads profile+teams via withSystem
export async function requireUser(): Promise<SessionUser>;               // redirect('/login') when null
export type Capability =
  | 'activity.create' | 'verify.partnership' | 'verify.mobility' | 'duplicates.view' | 'duplicates.manage'
  | 'known.view' | 'known.manage' | 'settings.manage' | 'reports.view' | 'export.participants'
  | 'export.snapshot' | 'export.known' | 'export.duplicates' | 'snapshot.archive';
export function can(user: SessionUser, cap: Capability): boolean;        // pure; mirrors Rules §10 (io_admin = all)
export async function getToday(): Promise<string>;                       // realisasi.today()::text via withSystem (cached per request)
export async function getDemoToday(): Promise<string | null>;            // settings.demo_today
```
Capability matrix: `activity.create` submitter, io_admin · `verify.partnership`/`duplicates.manage`/`known.manage` io_admin or team partnership · `verify.mobility` io_admin or team mobility · `duplicates.view`/`known.view` io_staff, io_admin · `settings.manage` io_admin · `reports.view` all · `export.participants` submitter, team mobility, io_admin · `export.snapshot`/`snapshot.archive` io_staff, io_admin, viewer · `export.known`/`export.duplicates` io_staff, io_admin.

`lib/realisasi/actions/session.ts` (`'use server'`): `loginAs(profileId: string): Promise<void>` (validates id is a demo account; sets httpOnly, `sameSite:'lax'`, path `/`, 7-day cookie; `redirect('/realisasi')`), `logout(): Promise<void>` (delete cookie; `redirect('/login')`).

`middleware.ts`: matcher `['/((?!_next/|favicon.ico|login).*)']`; no `demo_uid` cookie → `/api/*` returns `401 {"code":"AUTH_REQUIRED","message":"…"}`, others redirect to `/login`. No DB access in middleware.

### 6.4 `lib/storage.ts` (FOUNDATION)

```ts
export const BUCKETS = { files: 'realisasi-files', transcripts: 'realisasi-transcripts' } as const;
export type Bucket = (typeof BUCKETS)[keyof typeof BUCKETS];
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
export type UploadPolicy = 'pdf' | 'pdf_or_image';
export function validateUpload(file: { name: string; type: string; size: number }, policy: UploadPolicy, firstBytes?: Uint8Array)
  : { ok: true } | { ok: false; code: 'R13_FILE_TOO_LARGE' | 'R13_FILE_TYPE'; message: string };
export function newActivityFilePath(activityId: string, kind: 'ia' | 'ir' | 'evidence', filename: string): string; // realisasi-files/<id>/<kind>/<uuid>.<ext>
export function newTranscriptPath(activityId: string, version: number, nrp: string): string;                    // realisasi-transcripts/<id>/v<n>/<nrp>-<8hex>.pdf
export async function putObject(tx: Tx, path: string, data: Buffer, mime: string): Promise<void>;   // select realisasi.storage_put($1,$2,$3)
export async function getObject(tx: Tx, path: string): Promise<{ data: Buffer; mime: string; size: number }>; // storage_get; DB errors propagate
export function fileHref(path: string): string;                                                    // '/api/files/' + path (segments URI-encoded)
```

### 6.5 `lib/realisasi/types.ts` (FOUNDATION) — must export exactly these names

Enums (string unions mirroring SQL): `ActivityStatus`, `TrackStatus`, `Direction`, `ActivityMode`, `FundingSource`, `FileKind`, `PersonRole`, `StudentSection`, `PsetStatus` (incl. `'draft'`), `KnownSource`, `KnownStatus`, `SemesterTerm`, `SnapshotKind`, `DupStatus`, `LogKind`, `Team`, `Role` (re-export), `SlaLevel = 'ok' | 'yellow' | 'red'`, `Period = 'ganjil' | 'full' | 'live'`, `KpiCode = '1.1' | '1.19.S1' | '1.19.24' | '1.19.S8'`, `DrilldownKpi = KpiCode | 'base'`, `RejectReason = 'duplicate' | 'not_partnership' | 'wrong_agreement' | 'other'`.
Aliases: `DateString = string`, `Timestamp = string`, `Uuid = string`.
Payloads: `ActivityDetailPayload`, `ExternalPersonPayload`, `StudentRowPayload`, `StaffRowPayload`, `RowNotePayload`, `KnownActivityPayload`, `ActivityTypePayload`, `SettingsValues` (all §2.3 keys, `demo_today: DateString | null`).
Results/read models (field-for-field from §3/§4): `ActivityStatusResult`, `SubmitResult`, `SaveParticipantsResult`, `ChecklistItem`, `RegisteredFile`, `DocumentOption`, `StudentRecord` (mock_baak row), `EmployeeRecord`, `ActivityListRow` (= `v_activity_list`), `ActivityDetail`, `ActivityPermissions`, `ParticipantVersion`, `ParticipantStudentRow`, `ParticipantStaffRow`, `ParticipantCounts`, `KpiTriple` (`{numerator, denominator, grace_excluded, pct}`), `KpiValues`, `KpiCharts`, `UnitKpiValues`, `PeriodInfo`, `DashboardData`, `ActivityKpiRow`, `ChainKpiRow`, `KnownKpiRow`, `DrilldownResult`, `KpiParticipantRow`, `SnapshotListRow`, `SnapshotDetail`, `LateAdditionRow`, `PostFreezeChangeRow`, `AgreementRealization`, `AgreementFlag`, `KnownActivityRow` (= `v_known_activities`), `KnownSuggestion`, `DuplicateCandidateRow` (= `v_duplicate_candidates`), `NavCounts`, `NotificationRow`, `DailyJobsResult`, `ActivityLogEntry`.
Also: `ExportKind` (union in §8.2), and `export type ActionResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string; detail?: unknown };`

### 6.6 `status.ts`, `format.ts`, `errors.ts` (FOUNDATION)

```ts
// lib/realisasi/status.ts
export type Tone = 'neutral' | 'blue' | 'amber' | 'green' | 'red' | 'purple' | 'yellow';
export const ACTIVITY_STATUS_LABEL: Record<ActivityStatus, string>; // Draf · Dalam Verifikasi · Perlu Revisi · Terverifikasi · Ditolak
export const ACTIVITY_STATUS_TONE: Record<ActivityStatus, Tone>;    // neutral · blue · amber · green · red
export const TRACK_STATUS_LABEL: Record<TrackStatus, string>;       // Tidak diperlukan · Menunggu · Perlu Revisi · Disetujui · Ditolak
export const TRACK_STATUS_TONE: Record<TrackStatus, Tone>;          // neutral · blue · amber · green · red
export const TRACK_LABEL: Record<Team, string>;                     // Kemitraan · Mobilitas
export const PSET_STATUS_LABEL: Record<PsetStatus, string>;         // Draf · Menunggu · Perlu Revisi · Disetujui · Digantikan
export const KNOWN_STATUS_LABEL: Record<KnownStatus, string>;       // Belum dilaporkan · Cocok · Diabaikan
export const KNOWN_SOURCE_LABEL: Record<KnownSource, string>;       // Surat Tugas · Berita · Laporan Fakultas · LoA/Surat Visa · Email · Lainnya
export const DUP_STATUS_LABEL: Record<DupStatus, string>;           // Terbuka · Ditautkan · Bukan duplikat
export const REJECT_REASON_LABEL: Record<RejectReason, string>;     // Duplikat · Bukan kegiatan kerja sama · Kerja sama salah · Lainnya
export const DIRECTION_LABEL, MODE_LABEL, FUNDING_LABEL, PERSON_ROLE_LABEL, FILE_KIND_LABEL, SECTION_LABEL,
             SNAPSHOT_KIND_LABEL, PERIOD_LABEL, ROLE_LABEL, LOG_KIND_LABEL, LOG_ACTION_LABEL: Record<…, string>;
export const SLA_TONE: Record<SlaLevel, Tone>;                      // ok→neutral, yellow→yellow, red→red
export function slaText(days: number): string;                      // 'SLA 4 hari'
export const FLAG_LABEL = { late: 'Terlambat', out_of_scope: 'Di luar lingkup', duplicate: 'Duplikat?', late_addition: 'Tambahan susulan' } as const;

// lib/realisasi/format.ts  (Asia/Jakarta, id-ID)
export function formatDate(d: DateString | Timestamp | null | undefined): string;     // '14 Sep 2026' ; '–' for null
export function formatDateNumeric(d: DateString | Timestamp | null | undefined): string; // '14-09-2026'
export function formatDateTime(ts: Timestamp | null | undefined): string;             // '14 Sep 2026 10:42'
export function formatNumber(n: number | null | undefined): string;                  // '1.234'
export function formatPct(n: number | null | undefined): string;                     // '62,3%' ; '–'
export function formatBytes(n: number): string;                                      // '1,2 MB'
export function durationDays(start: DateString, end: DateString): number;            // inclusive
export function exportFilename(kind: string, periodLabel: string, at?: Date): string; // SIM-Realisasi_{kind}_{period}_{yyyyMMdd-HHmm}.xlsx (period sanitized: spaces/slashes → '-')

// lib/realisasi/errors.ts
export interface AppError { code: string; message: string; detail?: unknown }
export function parseDbError(e: unknown): AppError;     // /^([A-Z0-9_]+): (.*)$/s on e.message; detail = JSON.parse(e.detail) when possible; else INTERNAL (logs original)
export function httpStatusFor(code: string): number;   // AUTH_REQUIRED 401; AUTH_FORBIDDEN/FILE_FORBIDDEN 403; NOT_FOUND/FILE_NOT_FOUND 404; RATE_LIMITED 429; INTERNAL 500; others 400
export async function runAction<T>(fn: () => Promise<T>): Promise<ActionResult<T>>;
export function errorResponse(e: unknown): Response;    // JSON {code,message,detail} with httpStatusFor
export const ERROR_MESSAGES: Record<string, string>;    // fallback Indonesian text for every code in §2.9 + app-only codes
```

### 6.7 Calling conventions (all WPs)

```ts
// server action pattern ('use server' modules under lib/realisasi/actions/)
export async function submitActivity(id: string): Promise<ActionResult<SubmitResult>> {
  const user = await requireUser();
  const res = await runAction(() => withUser(user.id, async (tx) => {
    const [row] = await tx`select realisasi.submit_activity(${id}::uuid) as r`;
    return row!.r as SubmitResult;
  }));
  if (res.ok) revalidatePath('/realisasi', 'layout');
  return res;
}
```
- Always positional args with explicit casts (`::uuid`, `::int`, `::date`, `::text[]`, `::jsonb`); jsonb via `${tx.json(obj)}::jsonb`; bytea via a `Buffer`.
- Set-returning functions: `select * from realisasi.fn(…)`.
- Never compute KPIs or permissions in TS; read them from the RPCs.
- Every page/route calls `requireUser()` then does all DB work inside one `withUser`.
- Next 15: `params`/`searchParams` are Promises — `const { id } = await props.params`.

### 6.8 Cross-WP module signatures

**WP-SUBMIT**
```ts
// lib/realisasi/schemas/activity.ts
export const activityDetailSchema: z.ZodType<ActivityDetailPayload>;     // client+server; Indonesian messages
export const evidenceLinkSchema: z.ZodObject<{ url: …; label: … }>;
// lib/realisasi/schemas/participants.ts
export const studentRowSchema, staffRowSchema, participantsSchema;         // → StudentRowPayload[], StaffRowPayload[]
export function parseIdList(text: string): string[];                     // split lines/commas, trim, upper-case, unique-preserving order
// lib/realisasi/actions/submission.ts ('use server')
saveActivityDraft(id: string | null, data: ActivityDetailPayload): Promise<ActionResult<{ id: string }>>
deleteDraft(id: string): Promise<ActionResult<null>>
ensureParticipantDraft(activityId: string): Promise<ActionResult<{ version_id: string; version: number }>>
saveParticipants(activityId: string, students: StudentRowPayload[], staff: StaffRowPayload[]): Promise<ActionResult<SaveParticipantsResult>>
submitActivity(id: string): Promise<ActionResult<SubmitResult>>
editVerifiedActivity(id: string, data: Partial<ActivityDetailPayload>, note: string): Promise<ActionResult<{ diff: Record<string, unknown>; in_frozen_period: boolean }>>
commitParticipantEdit(activityId: string, note: string): Promise<ActionResult<{ version: number; diff: unknown; in_frozen_period: boolean }>>
addEvidenceLink(activityId: string, url: string, label: string): Promise<ActionResult<RegisteredFile>>
removeActivityFile(fileId: number): Promise<ActionResult<null>>
// lib/realisasi/queries/activity.ts
getActivityDetail(tx: Tx, id: string): Promise<ActivityDetail | null>     // null on NOT_FOUND
getParticipantVersion(tx: Tx, activityId: string, version?: number): Promise<ParticipantVersion | null>
// lib/realisasi/queries/lookups.ts
getFormOptions(tx: Tx): Promise<{ activityTypes: …[]; units: …[]; countries: …[]; sdgs: …[]; academicYears: (… & { semesters: … })[] }>
// components (client unless noted)
components/realisasi/activity/detail-summary.tsx  export function ActivityDetailSummary(p: { detail: ActivityDetail; compact?: boolean }): JSX.Element   // server-safe (no hooks)
components/realisasi/activity/file-list.tsx       export function FileList(p: { files: ActivityDetail['files']; showHistory?: boolean }): JSX.Element
components/realisasi/activity/participant-table.tsx export function ParticipantTable(p: { version: ParticipantVersion; highlight?: Record<string, 'added' | 'removed' | 'changed'>; removedRows?: ParticipantStudentRow[]; editableRowNotes?: boolean; onRowNoteChange?: (kind: 'student' | 'staff', id: string, note: string) => void }): JSX.Element
```

**WP-VERIFY**
```ts
// lib/realisasi/schemas/filters.ts
export interface ActivityListFilters { q?: string; status?: ActivityStatus[]; type_id?: number; unit_id?: number; country?: string;
  ay?: number; semester?: number; partnership?: TrackStatus; mobility?: TrackStatus; late?: boolean; sla?: 'yellow' | 'red';
  from?: DateString; to?: DateString; preset?: 'mine' | 'late' | 'this_semester'; queue?: 'partnership' | 'mobility';
  sort?: 'start_desc' | 'start_asc' | 'code' | 'sla' }
export const activityListFiltersSchema: z.ZodType<ActivityListFilters>;
export function parseActivityFilters(sp: URLSearchParams | Record<string, string | string[] | undefined>): ActivityListFilters;
export function activityFiltersToSearchParams(f: ActivityListFilters): URLSearchParams;  // status as comma list
// URL keys = field names; booleans '1'; arrays comma-separated.
// lib/realisasi/queries/activities.ts
export async function listActivities(tx: Tx, user: SessionUser, f: ActivityListFilters): Promise<ActivityListRow[]>;
//   from realisasi.v_activity_list; no pagination; hard limit 2000; default sort start_desc; queue=partnership → partnership_status='pending' order by partnership_sla_days desc nulls last;
//   preset mine: submitter → own-unit drafts + revision_requested; partnership → P pending; mobility → M pending; io_admin → either pending
//   preset this_semester: semester containing today(); preset late: is_late or (draft and reporting_deadline < today())
export function describeActivityFilters(f: ActivityListFilters, opts: { typeName?: (id: number) => string; unitName?: (id: number) => string }): Array<[label: string, value: string]>;
// lib/realisasi/schemas/known.ts
export interface KnownFilters { q?: string; status?: KnownStatus; unit_id?: number; intl?: boolean; from?: DateString; to?: DateString }
export function parseKnownFilters(sp): KnownFilters;  export const knownActivitySchema: z.ZodType<KnownActivityPayload>;
// lib/realisasi/queries/known.ts
export async function listKnownActivities(tx: Tx, f: KnownFilters): Promise<KnownActivityRow[]>;
// lib/realisasi/queries/duplicates.ts
export async function listDuplicateCandidates(tx: Tx, f: { status?: DupStatus }): Promise<DuplicateCandidateRow[]>;  // default 'open'
// lib/realisasi/participant-diff.ts
export function diffParticipantVersions(prev: ParticipantVersion | null, next: ParticipantVersion): { students: Array<{ key: string; change: 'added' | 'removed' | 'changed' | 'same'; before?: ParticipantStudentRow; after?: ParticipantStudentRow; changedFields: string[] }>; staff: …same with ParticipantStaffRow };
// lib/realisasi/actions/verification.ts ('use server')
partnershipApprove(id, note?), partnershipRequestRevision(id, note), partnershipReject(id, reason: RejectReason, note),
mobilityApprove(id, note?), mobilityRequestRevision(id, note, rowNotes: RowNotePayload[])  → Promise<ActionResult<ActivityStatusResult>>
// lib/realisasi/actions/duplicates.ts: linkDuplicates(candidateId, note?), linkActivities(a, b, note), dismissDuplicate(candidateId, note?), unlinkActivity(id, note)
// lib/realisasi/actions/known.ts: createKnownActivity(data), updateKnownActivity(id, data), matchKnownActivity(id, activityId), unmatchKnownActivity(id), dismissKnownActivity(id, note), nudgeKnownActivity(id), getKnownSuggestions(id) → ActionResult<KnownSuggestion[]>
// components (client)
components/realisasi/verify/partnership-actions.tsx export function PartnershipActions(p: { activityId: string; code: string; permissions: ActivityPermissions }): JSX.Element | null
components/realisasi/verify/mobility-actions.tsx    export function MobilityActions(p: { activityId: string; code: string; version: ParticipantVersion | null; previous: ParticipantVersion | null; permissions: ActivityPermissions }): JSX.Element | null
components/realisasi/verify/duplicate-actions.tsx   export function DuplicateActions(p: { activityId: string; permissions: ActivityPermissions; duplicates: ActivityDetail['duplicates'] }): JSX.Element | null
```

**WP-REPORTS**
```ts
// lib/realisasi/schemas/report.ts
export interface PeriodParams { ay?: number; period: Period; unit?: number; snapshot?: string }
export function parsePeriodParams(sp): PeriodParams;
// lib/realisasi/queries/reports.ts
getDashboard(tx, p: PeriodParams): Promise<DashboardData>; getDrilldown(tx, p: PeriodParams & { kpi: DrilldownKpi; bucket?: string }): Promise<DrilldownResult>;
getSnapshotList(tx, ay?: number): Promise<SnapshotListRow[]>; getSnapshotDetail(tx, id: string): Promise<SnapshotDetail>;
getAgreementRealization(tx, documentId: number): Promise<AgreementRealization>; getAgreementFlags(tx, ay?: number): Promise<AgreementFlag[]>;
// lib/realisasi/actions/settings.ts ('use server'): updateSettings, upsertAcademicYear, upsertSemester, upsertActivityType, upsertHoliday, deleteHoliday, freezeNow(ay, kind), refreeze(snapshotId, reason), runDailyJobs()
// lib/excel/workbook.ts
export function createWorkbook(): ExcelJS.Workbook;
export interface InfoSheet { kind: string; title: string; filters: Array<[string, string]>; generatedBy: string; generatedAt: Date; dataAsOf: string; rowCount: number }
export function addInfoSheet(wb, info: InfoSheet): void;                       // always first sheet, name 'Info'
export interface Column<R> { header: string; key: string; width?: number; value: (row: R) => string | number | Date | boolean | null; format?: 'date' | 'pct' | 'int' | 'text' }
export function addTableSheet<R>(wb, name: string, columns: Column<R>[], rows: R[]): ExcelJS.Worksheet;  // bold frozen header, autofilter, fitted widths, dd-mm-yyyy, 0.0%
export async function toBuffer(wb): Promise<Buffer>;
// lib/excel/registry.ts
export interface ExportContext { tx: Tx; user: SessionUser; params: URLSearchParams }
export interface ExportResult { workbook: ExcelJS.Workbook; periodLabel: string; rowCount: number; containsPersonal: boolean; filters: Record<string, unknown> }
export const EXPORTS: Record<ExportKind, { allowed: (u: SessionUser) => boolean; build: (ctx: ExportContext) => Promise<ExportResult> }>;
```

### 6.9 Shared UI components (FOUNDATION)

`components/ui/`: `button`, `input`, `textarea`, `label`, `select` (Radix), `native-select`, `checkbox`, `switch`, `radio-group`, `badge` (variants = `Tone` + `outline`), `card`, `table` (Table, TableHeader, TableBody, TableRow, TableHead, TableCell), `tabs`, `dialog`, `alert-dialog`, `sheet` (side panel on Radix dialog), `dropdown-menu`, `popover`, `command` (cmdk), `combobox` (multi-select on popover+command), `tooltip`, `alert`, `separator`, `skeleton`, `collapsible`, `form` (react-hook-form `Form, FormField, FormItem, FormLabel, FormControl, FormMessage, FormDescription`), `stepper`, `toaster` (sonner wrapper; `toast` re-export), `file-drop` (drop zone: `accept`, `maxBytes`, `onFiles`).

`components/realisasi/` (FOUNDATION): `status-badge.tsx` → `StatusBadge({status})`, `TrackChips({partnership, mobility})`, `FlagPill({flag: keyof FLAG_LABEL, title?})`, `SlaChip({days, level})`, `PsetBadge({status})`; `page-header.tsx` → `PageHeader({title, description?, actions?})`; `empty-state.tsx` → `EmptyState({title, description?, action?})`; `export-button.tsx` → `ExportButton({kind, params?: URLSearchParams | Record<string,string>, label?: string})` renders `<a data-testid="export-excel" href="/api/export/{kind}?{params}" download>Unduh Excel</a>`; `country-flag.tsx` → `CountryFlag({code, name?})` (emoji flag + code); `forbidden.tsx` → `Forbidden()` ("Anda tidak memiliki akses ke halaman ini."); `notification-bell.tsx`; `demo-today-banner.tsx`.

`components/layout/`: `app-shell.tsx` (`AppShell({user, navCounts, demoToday, children})`), `sidebar.tsx` (Design §1 items + badges), `topbar.tsx` (bell, user menu with "Ganti akun" → logout).

**Test ids (stable, used by e2e):** login buttons `login-<email>`; `export-excel`; list counters `list-total` (text = number); KPI cards `kpi-card-1.1`, `kpi-card-1.19.S1`, `kpi-card-1.19.24`, `kpi-card-1.19.S8` with value element `kpi-value`; status badge `status-badge`; wizard buttons `wizard-next`, `wizard-save-draft`, `wizard-submit`; NRP check button `check-nrp`; action buttons `action-approve`, `action-request-revision`, `action-reject`, `action-resubmit`; nav links `nav-<route-segment>`.

---

## 7. Route map (`app/`)

| Route | File | Owner | Access / notes |
|---|---|---|---|
| `/` | `app/page.tsx` | FOUNDATION | redirect `/realisasi` |
| `/login` | `app/(auth)/login/page.tsx` | FOUNDATION | lists 8 accounts (role, unit, teams); click → `loginAs` |
| `/realisasi` (layout) | `app/realisasi/layout.tsx` | FOUNDATION | `requireUser`, `AppShell`, `nav_counts()` |
| `/realisasi` | `app/realisasi/page.tsx` | REPORTS | Dashboard; `?ay=&period=ganjil|full|live&unit=` |
| `/realisasi/kegiatan` | `app/realisasi/kegiatan/page.tsx` | VERIFY | list; filters per §6.8 in searchParams |
| `/realisasi/kegiatan/baru` | `app/realisasi/kegiatan/baru/page.tsx` | SUBMIT | `can('activity.create')`; `?draft=<id>&step=1..4`; io_admin picks unit |
| `/realisasi/kegiatan/[id]` | `app/realisasi/kegiatan/[id]/page.tsx` | SUBMIT | `?tab=detail|peserta|berkas|riwayat&v=<version>`; action bar embeds VERIFY components |
| `/realisasi/kegiatan/[id]/revisi` | `…/[id]/revisi/page.tsx` | SUBMIT | unit revision view (Detail/Berkas if P revision, Peserta if M revision or R-24 case) + "Ajukan ulang" |
| `/realisasi/kegiatan/[id]/edit` | `…/[id]/edit/page.tsx` | SUBMIT | IO post-verification Detail/Berkas edit (`can_edit_verified_detail`) |
| `/realisasi/kegiatan/[id]/peserta-edit` | `…/[id]/peserta-edit/page.tsx` | SUBMIT | IO Mobility post-verification participants edit (`can_edit_verified_participants`) |
| `/realisasi/verifikasi/kemitraan` | `app/realisasi/verifikasi/kemitraan/page.tsx` | VERIFY | `verify.partnership` |
| `/realisasi/verifikasi/mobilitas` | `…/mobilitas/page.tsx` | VERIFY | `verify.mobility` |
| `/realisasi/verifikasi/duplikat` | `…/duplikat/page.tsx` | VERIFY | `duplicates.view` (actions need `duplicates.manage`) |
| `/realisasi/kegiatan-diketahui` | `app/realisasi/kegiatan-diketahui/page.tsx` | VERIFY | `known.view` (actions need `known.manage`) |
| `/realisasi/laporan` | `app/realisasi/laporan/page.tsx` | REPORTS | `?report=ringkasan|kpi|kegiatan|peserta|register|realisasi-kerjasama|sla|arsip` + period params; `kpi=&bucket=`; `snapshot=<id>` |
| `/realisasi/pengaturan` | `app/realisasi/pengaturan/page.tsx` | REPORTS | `settings.manage`; `?tab=umum|kalender|jenis|libur` |
| `/realisasi/notifikasi` | `app/realisasi/notifikasi/page.tsx` | FOUNDATION | own notifications, mark read |
| `/kerjasama/dokumen` | `app/kerjasama/dokumen/page.tsx` | REPORTS | minimal SIM Kerjasama document list + "Belum ada realisasi tahun akademik ini" flag (`agreement_flags`) |
| `/kerjasama/dokumen/[id]` | `app/kerjasama/dokumen/[id]/page.tsx` | REPORTS | redirect to `…/realisasi` |
| `/kerjasama/dokumen/[id]/realisasi` | `app/kerjasama/dokumen/[id]/realisasi/page.tsx` | REPORTS | Realisasi tab (Design §3.10) |

Unauthorized page access renders `<Forbidden />` (HTTP 200 page, no data fetched). Sidebar also links "SIM Kerjasama → Dokumen" (`/kerjasama/dokumen`).

---

## 8. API routes & Excel exports

### 8.1 Non-export routes (WP-SUBMIT; all `runtime='nodejs'`, `requireUser`-equivalent returning 401 JSON)

| Route | Request | Response |
|---|---|---|
| `POST /api/lookup/students` | `{"nrps": string[] (≤200), "section": "internal"|"inbound"}` | `{"results":[{"nrp","status":"ok"|"not_found"|"graduated"|"inactive"|"not_inbound"|"is_inbound"|"duplicate","blocking":bool,"student":StudentRecord|null}]}` — `not_found`, `not_inbound` (inbound section with regular NRP), `is_inbound` (internal section with inbound NRP), `duplicate` are blocking; graduated/inactive are warnings. Rate limit 60 req/min/user → 429 `RATE_LIMITED`. |
| `POST /api/lookup/employees` | `{"ids": string[]}` | `{"results":[{"employee_id","status":"ok"|"not_found"|"inactive"|"duplicate","blocking":bool,"employee":EmployeeRecord|null}]}` |
| `GET /api/lookup/documents?start=&end=&unit_id=` | dates required | `{"documents": DocumentOption[]}` |
| `POST /api/upload` | multipart: `activity_id`, `target` = `ia`|`ir`|`evidence`|`transcript`, `file`, and `nrp` (transcript) | ia/ir/evidence: `validateUpload` → `putObject(newActivityFilePath)` → `register_activity_file` in one `withUser` tx → `200 RegisteredFile`. transcript: `ensure_participant_draft` → `putObject(newTranscriptPath(version))` → `200 {"path","href","version"}` (client then includes `transcript_path` in `saveParticipants`). Errors → `errorResponse`. |
| `GET /api/files/[...path]` | path = full storage path | `storage_get` → bytes with `Content-Type`, `Content-Disposition: inline; filename="…"`, `Cache-Control: private, no-store`; 403/404 per error code. |
| `GET /api/template/peserta?kind=students|staff` | — | `.xlsx` template (one column `NRP` / `ID Pegawai`) built with exceljs. |

### 8.2 `GET /api/export/[kind]` (WP-REPORTS)

Flow: `requireUser` (401) → unknown kind 404 → `EXPORTS[kind].allowed(user)` false → **403** `{"code":"AUTH_FORBIDDEN"}` (AT-11) → `withUser` build → `log_export(kind, filters, rowCount, containsPersonal)` → stream with `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `Content-Disposition: attachment; filename="<exportFilename(kind, periodLabel)>"`.
Every workbook: first sheet **Info** (Jenis ekspor, Judul, each filter as its own row "Filter: <label>" → value, Dibuat oleh, Dibuat pada, Data per (`Live s.d. <today>` or `Snapshot <label> · dibekukan <frozen_at> · id <uuid>`), Jumlah baris). Header row bold + frozen + autofilter; dates `dd-mm-yyyy`; percentages 1 decimal.
Query params: the **same** keys the page uses (so "Unduh Excel" = `/api/export/<kind>?<current searchParams>`). Period params: `ay`, `period`, `unit`, `snapshot`. Submitters are always forced to their unit for KPI/dashboard kinds.

| kind | Params | Access (else 403) | Personal | Sheets → columns |
|---|---|---|---|---|
| `activities` | activity list filters (§6.8) | all roles (RLS scopes rows) | no | **Kegiatan**: Kode · Nama Kegiatan · Jenis Kegiatan · Unit Pengaju · Unit Lain · No. Dokumen Kerja Sama · Mitra · Negara · Tanggal Mulai · Tanggal Selesai · Semester · Tahun Akademik · Moda · Status · Status Kemitraan · Status Mobilitas · SLA Kemitraan (hari kerja) · SLA Mobilitas (hari kerja) · Terlambat · Batas Pelaporan · Diajukan · Diverifikasi. Rows = `listActivities(filters)` (identical to screen, AT-12). |
| `participants` | activity list filters + `version=approved|latest` (default approved) | submitter, mobility team, io_admin | **yes** | **Mahasiswa**: Kode Kegiatan · Nama Kegiatan · Jenis · Arah · Tanggal Mulai · Unit Pengaju · Versi · Status Versi · Bagian (PETRA/Inbound) · NRP · Nama · Fakultas · Prodi · Institusi Asal · No. Mahasiswa Asal · Negara Asal. **Pegawai**: Kode Kegiatan · Nama Kegiatan · Versi · ID Pegawai · Nama · Unit. |
| `kpi-summary` | `ay, period, unit` | all | no | **Ringkasan**: KPI · Uraian · Nilai · Pembilang · Penyebut · Masa Tenggang · Catatan (one row per KPI and per 1.19.24 scope all/intl/domestic, 1.1 inbound/outbound/total, S1 intl/domestic). **1.1**: Kode · Nama · Jenis · Arah · Unit · Mitra · Negara · Tanggal Mulai · Semester · Grup Kegiatan · Jumlah Mahasiswa · Tambahan Susulan. **1.19.S1**: Kode · Nama · Jenis · Unit · Mitra · Negara · Tanggal Mulai · Semester · Kategori (Internasional/Domestik) · Kegiatan Tertaut · Tambahan Susulan. **1.19.24**: ID Rantai · No. Dokumen (saat ini) · Dokumen dalam Rantai · Jenis (MoU/MoA) · Judul · Mitra · Negara · Internasional · Mulai Rantai · Akhir Rantai · Perpanjangan Otomatis · Status (Terlaksana / Belum terlaksana / Masa tenggang) · Masa Tenggang s.d. · Kegiatan (kode). **1.19.S8**: Jenis Baris (Dilaporkan / Belum dilaporkan) · Kode/ID · Judul · Tanggal · Unit · Mitra · Negara · Sumber. Data = `dashboard()` + `kpi_drilldown()` for each KPI. |
| `kpi-drilldown` | `ay, period, unit, snapshot, kpi, bucket` | all | no | one sheet named by KPI code with that KPI's columns above. |
| `chart` | `ay, period, unit, chart=mobility_by_semester|by_country|by_unit|by_sdg|realization_by_unit|top_partners` | all | no | one sheet: the chart's array fields as columns (Indonesian headers). |
| `snapshot` | `snapshot=<uuid>` | io_staff, io_admin, viewer | only if `1.1 Peserta` included (mobility team / io_admin) | **Ringkasan**, **1.1**, **1.19.S1**, **1.19.24**, **1.19.S8** (as kpi-summary, from snapshot items via `kpi_drilldown(p_snapshot_id)`), **Tambahan Susulan** (Kode · Nama · Unit · Tanggal Mulai · Diverifikasi · Snapshot Sebelumnya · Dihitung di Snapshot Ini · KPI), **Perubahan Pasca-Beku** (Waktu · Kode · Nama · Jalur · Aksi · Oleh · Catatan · Perubahan (field: lama → baru)), **1.1 Peserta** (mobility/io_admin only; `kpi_participant_rows`). Info adds frozen_at, frozen_by, superseded state, refreeze reason, `settings_used`. |
| `snapshot-archive` | `ay` | io_staff, io_admin, viewer | no | **Arsip Snapshot**: Tahun Akademik · Jenis · Jendela · Cutoff · Dibekukan pada · Oleh · Status (Berlaku/Digantikan) · Alasan Bekukan Ulang · 1.1 Total · 1.19.S1 Internasional · 1.19.24 % · 1.19.S8 % · Tambahan Susulan · Perubahan Pasca-Beku. |
| `realization-by-agreement` | `ay, period, unit, status=realized|not_realized|grace_excluded` | all | no | **Realisasi per Kerja Sama**: 1.19.24 columns + Jumlah Kegiatan · Kegiatan Terakhir. |
| `sla` | activity list filters | all roles (RLS scopes rows) | no | **SLA Verifikasi** (one row per submitted activity per track): Kode · Nama · Unit · Jalur · Status Jalur · Sejak · Hari Kerja · Level (Normal/Kuning/Merah) · Ambang Kuning · Ambang Merah. |
| `known-activities` | known filters (§6.8) | io_staff, io_admin | no | **Register**: ID · Tanggal · Judul · Unit · Mitra · Negara · Internasional · Sumber · Referensi · Status · Kegiatan SIM (Kode) · Diingatkan · Dicatat oleh · Dicatat pada. |
| `duplicates` | `status` | io_staff, io_admin | no | **Kandidat Duplikat**: Skor · Kode A · Nama A · Unit A · Tanggal A · Kode B · Nama B · Unit B · Tanggal B · Status · Diselesaikan oleh · Diselesaikan pada. |
| `agreement-activities` | `document_id` | all | no | **Realisasi Kerja Sama**: Kode · Nama · Jenis · Tanggal Mulai · Tanggal Selesai · Status · Unit · Dokumen saat Kegiatan · Dokumen Saat Ini. |

`type ExportKind = 'activities' | 'participants' | 'kpi-summary' | 'kpi-drilldown' | 'chart' | 'snapshot' | 'snapshot-archive' | 'realization-by-agreement' | 'sla' | 'known-activities' | 'duplicates' | 'agreement-activities'` (declared in `lib/realisasi/types.ts`).

Laporan page report → export kind: ringkasan → `kpi-summary`; kpi → `kpi-drilldown`; kegiatan → `activities`; peserta → `participants` (hidden unless `can('export.participants')`); register → `known-activities` (hidden unless `can('export.known')`); realisasi-kerjasama → `realization-by-agreement`; sla → `sla`; arsip → `snapshot-archive` / `snapshot` (hidden for submitters). Queue pages use `activities` with `queue=…`; Duplikat page uses `duplicates`; Register page uses `known-activities`; dashboard card ⋯ → `kpi-drilldown`, chart ⋯ → `chart`; Kerjasama tab → `agreement-activities`.

---

## Contract amendments (WP-FOUNDATION)

Additive only; nothing in §6 was removed or renamed.

1. **`lib/db.ts` parsers**: `timestamp` (1114, no time zone) is treated as UTC and returned as an ISO string, the same as `timestamptz`. Array variants (`date[]`, `timestamptz[]`, `int8[]`, `numeric[]`) use the same element parsers. Values inside `json`/`jsonb` are not touched, so they come back as whatever `to_jsonb()` produced. I checked this with `TZ=America/New_York`: `'2026-09-14'::date` → `'2026-09-14'`.
2. **`lib/session.ts`** also exports `findDemoAccount(id): Promise<DemoAccount | null>`, which `loginAs` uses. `getSessionUser`, `getToday` and `getDemoToday` are `React.cache` constants with the contract signatures.
3. **`lib/realisasi/errors.ts`** extras:
   - `isNextControlError(e)`: `runAction` **rethrows** Next `redirect()`/`notFound()` errors.
   - `appError(code, message?, detail?)`: an app-side throwable in the same `'<CODE>: msg'` shape as SQL errors.
   - `parseDbError` maps SQLSTATE `42501` → `AUTH_FORBIDDEN`, and `22P02`/`22007`/`22008` (bad uuid/date text) → `BAD_REQUEST`. All other unexpected errors → `INTERNAL`, as the contract says.
4. **`lib/realisasi/status.ts`** extras:
   - `ACTIVITY_STATUS_DESCRIPTION`, `PSET_STATUS_TONE`, `KNOWN_STATUS_TONE`, `DUP_STATUS_TONE`
   - `SLA_LEVEL_LABEL` (Normal/Kuning/Merah, for the `sla` export)
   - `FLAG_TONE`, `FLAG_DESCRIPTION`, type `FlagKey`
   - `logActionLabel(action)`, which falls back to the raw action
5. **`lib/realisasi/format.ts`** extras: `formatTime(ts)` and `daysBetween(from, to)`. All formatting is deterministic. Dates use hard-coded Indonesian month abbreviations (`Mei`, `Agu`, `Okt`, `Des`). Timestamps convert to WIB as UTC+7. `formatPct` always shows one decimal (`40,0%`). In `exportFilename`, characters outside `[A-Za-z0-9._()-]` are removed after spaces and slashes become `-`, and an empty period becomes `semua`.
6. **`lib/realisasi/types.ts`** extra named types:
   - `RegistryStudentStatus`, `RegistryEmployeeStatus`, `SaveParticipantsWarning`, `DocumentPartnerOption`
   - `ActivityFile`, `ParticipantVersionSummary`, `TrackSla`, `TrackRevision`
   - `MobilityBySemester`, `KpiParams`, `KpiScope`
   - `KpiValues.by_unit` is optional (present only at university level).
   - `ChecklistItem.late?` exists only on `LATE_NOTICE`.
   - `SaveParticipantsWarning.section` may be `'staff'` for inactive employees.
7. **`lib/utils.ts`**: `cn(...)` and `toQueryString(params)`, which returns `''` or `'?a=b'` and drops empty values.
8. **Notifications**: `lib/realisasi/actions/notifications.ts` exports `listNotifications({limit?, unreadOnly?})` and `markNotificationsRead(ids: number[] | null)`, which calls `mark_notifications_read`.
9. **Nav test ids** use the last route segment: `nav-realisasi` (Dashboard), `nav-kegiatan`, `nav-baru`, `nav-kemitraan`, `nav-mobilitas`, `nav-duplikat`, `nav-kegiatan-diketahui`, `nav-laporan`, `nav-pengaturan`, `nav-dokumen` (SIM Kerjasama). Badges are `nav-<seg>-badge`.
   - Nav visibility follows Design §1. "Duplikat" and "Kegiatan Diketahui" are shown only for `duplicates.manage`/`known.manage` (partnership + admin). Pages still allow `*.view` (all io_staff).
   - Submitters get a `revision_inbox` badge on "Kegiatan".
10. **Other shell test ids**: `user-menu`, `switch-account`, `logout`, `notification-bell`, `notification-count`, `notification-list`, `demo-today-banner`, `forbidden`, and `track-chip-partnership`/`track-chip-mobility`. The status badge also carries `data-status`.
11. **Shared UI extras**: `Badge` has an `appearance="solid|outline"` prop on top of the tone variants. `Button` has a `loading` prop. `SimpleTooltip` needs the `TooltipProvider` that the root layout mounts. Also available: `ToneDot` (status-badge.tsx), `flagEmoji(code)` (country-flag.tsx) and `inputClassName` (input.tsx).
    - `Combobox` props: `{options: {value: string, label, content?, keywords?, disabled?}[], value: string[], onChange, multiple?=true, …}`. Values are strings.
    - `Stepper` props: `{steps: {label, href?, disabled?, invalid?}[], current: 1-based}`.
    - `FileDrop` also accepts `onReject`, `multiple`, `label` and `hint`.
12. **`/kerjasama/**` pages (WP-REPORTS)** are not under `app/realisasi/layout.tsx`. To get the shell, wrap them in `AppShell` from `components/layout/app-shell.tsx` (needs `user`, `navCounts` from `realisasi.nav_counts()`, `demoToday`), or add `app/kerjasama/layout.tsx` that mirrors `app/realisasi/layout.tsx`.
13. **Playwright**: `e2e/helpers.ts` exports `ACCOUNTS`, `loginAs(page, email)` and `resetDb()`. Global setup runs `scripts/db-reset.sh` unless `E2E_SKIP_DB_RESET=1`. `webServer` runs `npm run dev`; override it with `E2E_SERVER_COMMAND`/`E2E_PORT`. The Chromium download (`npx playwright install chromium`) was blocked in the build sandbox.

---

## Contract amendments (WP-DB)

All RPC signatures in §3 are unchanged. The items below clarify behaviour or add internal objects. They are listed so app agents can rely on them.

1. **`auth.uid()` stub (§2.4).** The stub uses Supabase's own form: `coalesce(nullif(claim.sub,''), nullif(claims,'')::jsonb->>'sub')::uuid`. It tolerates an empty `request.jwt.claims` GUC, which a pooled connection has after a `withUser` transaction ends. The §2.4 body would raise `invalid input syntax for type json` in that case.
2. **`save_participants` transcripts (§3.2).** The contract allowed only paths under `v<draft version>/`. A non-null `transcript_path` is now also accepted when it already belongs to an earlier version of the same activity. Without this, rows copied by `ensure_participant_draft` (which keep their v1 paths) could never be re-saved. New uploads must still target the draft version (`storage_put` enforces this).
3. **Extra invariant.** There is a unique partial index `one_draft_pset` on `participant_set_versions(activity_id) where status='draft'`, so there is at most one draft version.
4. **Helpers granted to `authenticated`.** These are definer helpers, needed because the security-invoker views call them: `activity_linked_count(uuid)` (`v_activity_list.linked_count`, counted across RLS) and `activity_participant_total(uuid)` (`v_duplicate_candidates.*_participants`). Both return counts only. `alter default privileges … revoke execute on functions from public` is applied in schema `realisasi`.
5. **Internal objects added (not granted).** `realisasi.period_ctx` (composite type), `_business_days_ago(n)` (lives in 0003; used by seeds), `_kpi_items(…, p_grace_months)`, `_kpi_values`, `_freeze`, `_checklist` and similar.
6. **Snapshot labels.** `SnapshotListRow.label` / `previous_snapshot_label` / `snapshot_frozen` titles are `Ganjil 2025/2026 (YTD)` and `Genap 2025/2026 (Setahun)`. `PeriodInfo.label` stays as specified (`Setahun 2025/2026`). `frozen_by_name` is `Job terjadwal` when `frozen_by` is null.
7. **`PeriodInfo` for unfrozen periods.** `window_end` and `cutoff` are the effective values used for computing, `least(nominal, today())`. For `live`, `window_end = cutoff = least(AY end, today())`, so the Live view of a past AY stops at its AY end.
8. **`submission_checklist` items.** Every item carries a message: the error text when `ok=false` and a short positive Indonesian text when `ok=true`. `R07_REQUIRED_FIELD` also carries `"fields":[…]`. `LATE_NOTICE` text is `Batas pelaporan 13 Sep 2026 telah lewat — kegiatan akan ditandai Terlambat.`
9. **Logs.** Draft creation is logged as `system/create`, initial submit as `system/submit` (track null), resubmit as `revision/<track>/resubmit`. File changes are logged only in revision (`revision/partnership/file_upload|file_remove`) or verified (`update/partnership/…`) state. `dismiss_duplicate` writes `verification/partnership/dismiss_duplicate` on both activities.
10. **`commit_participant_edit`.** If the verified activity had `mobility_status='not_required'`, the track becomes `approved`. The overall status stays `verified`.
11. **Deadline reminders (§5.1).** Every applicable tag (`h7`/`h0`/`w<n>`) is marked once. Each run sends at most one notification per draft: the most advanced tag that is new in that run.
12. **`delete_draft`.** This also removes the draft's logs, its duplicate candidates and its blobs. Any known activity matched to it reverts to `unmatched`, which cannot happen for drafts but is handled defensively.
13. **`storage_put`.** For `realisasi-files`, the third path segment must be `ia|ir|evidence`, and paths containing `..` are rejected (`VALIDATION_INVALID`).
14. **`unlink_activity`.** Returns `{"event_group_id":"<new>","activity_ids":["<p_activity>"]}`. Calling it on an activity that has no linked partners raises `STATE_INVALID`.
15. **Tests and shared DB.** `scripts/db-test.sh` honours `DATABASE_URL`. While other agents use `sim_realisasi`, run `DATABASE_URL=…/sim_realisasi_<x> scripts/db-reset.sh && … scripts/db-test.sh`; `db-reset` creates the database when it is missing. Test files live in `supabase/tests/*.sql`, and the shared helpers are in `supabase/tests/_helpers.inc`, which is not executed directly.

### Review fixes (docs/reviews/database-review.md, 2026-10-01)

All RPC signatures are unchanged. Every JSON shape change below is additive or makes fields `null`/counts for roles that may not see the data.

16. **KPI dedupe (§4.2, R-38/R-39).** At both levels, 1.1 has one row per distinct `(nrp, event_group_id)` and S1/S8 have one row per event group, *within the scope*. A unit on two linked activities counts the event once, and each unit of a linked event counts it. The representative is the earliest `verified_at` (tie: smallest `code`) in the scope. Unit-level `by_country`, `by_sdg` and `top_partners` also count distinct event groups.
17. **Counted participant version.** 1.1 rows and `kpi_participant_rows` use the version that counted at `as_of`: the latest `approved`/`superseded` version with `reviewed_at <= as_of`, else the current approved one. For live reads this is the current approved version. Frozen exports no longer drift after post-freeze edits. `ref_id` stays `<activity_id>:<nrp>`.
18. **Chains (§2.7, §4.2).** `v_chains` gains the column `terminated_at`. `auto_renewed`/`terminated_at` are those of the chain's current *valid* document. A chain is "active" when `chain_start <= cutoff and ((auto_renewed and terminated_at is null) or chain_end >= from)`. The 1.19.24 numerator resolves chains from `original_document_id` at query time. `run_daily_jobs` refreshes `activity_documents.chain_id`.
19. **`documents_valid_between` (R-04).** A document is valid through its `terminated_at` when one is set. An auto-renewed document is open-ended until the day before its first valid successor starts. Otherwise it is valid through `end_date`.
20. **S8 gap (R-49/R-50).** `unmatched_known` = international entries in the window that are `unmatched`, **or** `matched` to an activity that is not verified as of `as_of` or not international. `partnership_reject` reverts the rejected activity's matches to `unmatched` and logs `verification/partnership/unmatch_known` (`diff: {"known_activity_ids":[…]}`).
21. **Participants during a Partnership revision.** The unit may open/save a new participant version whenever `partnership_status='revision_requested'`. That makes `permissions.can_edit_participants` true there, but never for `rejected` activities. `can_submit` is false for rejected activities. On promotion, older `pending` versions become `superseded`. New invariant: unique partial index `one_pending_pset`.
22. **`edit_verified_activity`.** A `type_id` change must satisfy R-11/R-12 with the approved set (`R11_PARTICIPANTS_REQUIRED` / `R12_*`). Name, date and agreement changes rescan duplicates. **`commit_participant_edit`** also enforces R-11.
23. **Files.** `storage_put` raises `FILE_FORBIDDEN` when the path is already referenced by `activity_files`/`participant_students` or was uploaded by another user. The uploader may still retry an unreferenced path. `register_activity_file` ignores `p_mime`/`p_size_bytes` and stores the blob's values. IA/IR must be `application/pdf` with the `%PDF-` magic (`R13_FILE_TYPE`).
24. **Snapshots (§4.4).** P = the snapshot of the immediately preceding period ((AY, ganjil) → (AY-1, genap_full_year); (AY, genap) → (AY, ganjil_ytd)) that was live at the snapshot's `frozen_at`, not the latest `frozen_at` of any period. `freeze_snapshot` honours `p_as_of`/`p_actor` only for the system caller: no JWT subject and the session role is not `authenticated`/`anon`, as for pg_cron, seeds and psql. For io_admin it uses `now_ts()`/`auth.uid()` and raises the **new error code `R55_BEFORE_CUTOFF`** (detail `{"cutoff_date"}`) before the semester cutoff. `run_daily_jobs` uses the same system-caller test, so an `authenticated` session with empty claims gets `AUTH_REQUIRED`.
25. **Link logs.** `link_duplicate` log rows are flagged `in_frozen_period` when the activity is verified and in a frozen window, so they are listed as post-freeze changes. After a merge, open candidates whose pair shares the group become `linked`. `link_duplicates` raises `STATE_INVALID` for draft/rejected activities. `unlink_activity` splits the remaining members into connected components of `linked` candidates; split-off components get a new group and their own `unlink_duplicate` log with `diff.split_from`. The return value is unchanged.
26. **Participant identifiers in logs (Rules §10).** Direct `activity_log` reads hide rows whose `diff` has `students`/`staff`/`row_notes` unless the caller is io_admin, in the mobility team, or a submitter of the activity. For other callers, `activity_detail.log[].diff` and `snapshot_post_freeze_changes[].diff` show counts instead: `{"students":{"added":n,"removed":m},"staff":{…}}` and `"row_notes": n`.
27. **Visibility in read RPCs.** `agreement_realization.activities` lists only activities the caller can view; the `summary` counts stay complete. In `kpi_drilldown(…,'1.19.S8')`, known rows for non-IO callers have `title`, `partner_name`, `source` and `source_reference` = `null`.
28. **Lookups.** `lookup_students`/`lookup_employees` are limited to submitters, io_admin and the mobility team (`AUTH_FORBIDDEN` otherwise) and accept at most 500 ids (`VALIDATION_INVALID`).
29. **Demo time travel (M9).** New table `realisasi.deployment_flags(key, enabled)`, with no grants and no RPC writes. `demo_today` applies to `today()`/`now_ts()` only when `demo_time_travel` is enabled. `update_settings` rejects a non-null `demo_today` otherwise (`SETTINGS_INVALID`); `null` is always accepted. The demo seed enables it. Production does not run seeds, so the flag is off. To disable it explicitly: `update realisasi.deployment_flags set enabled = false where key = 'demo_time_travel'`. New granted helper: `realisasi.demo_time_travel_enabled() returns boolean`.
30. **Other behaviour.** When `update_settings` changes `reporting_deadline_days`, it recomputes `reporting_deadline` of drafts. `known_match_suggestions` matches a known date anywhere in `[start_date - w, end_date + w]`. `business_days_between` is closed-form (same results). Every function's `search_path` is `realisasi, extensions, public, pg_temp`. On a submission/resubmission that reaches both teams, io_admin gets one "Pengajuan baru" (requirements-review L-4). Seeded freeze notifications are dated at `frozen_at`, and `05_notifications.sql` no longer adds hand-written `snapshot_frozen` rows (L-6).
31. **New granted helpers for RLS** (definer, set-returning, evaluated once per statement): `my_activity_ids()`, `visible_activity_ids()`, `my_pset_ids()`, `sees_participant_identifiers()`. New internal (ungranted) helpers: `_chain_map()`, `_kpi_items_scoped(…)`, `_pset_as_of(uuid, timestamptz)`, `_mask_log_diff(jsonb)`, `_is_system_caller()`, `_check_pset_for_type(uuid, int)`, `_notify_team_except(…)`, `_require_registry_reader(int)`, `_demo_today()`. `_prev_snapshot` now takes `(ay, kind, before)`.
32. **New test files:** `12_state_review.sql`, `23_kpi_review.sql`, `31_snapshots_review.sql`, `41_access_review.sql`, `61_dup_review.sql`, `80_perf.sql` (scaled copy plus timing budgets, rolled back).
