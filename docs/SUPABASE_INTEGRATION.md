# Supabase integration — SIM Realisasi inside `simks-partnership`

Decision (user, 2026-10-01): deploy SIM Realisasi into the live SIM Kerjasama Supabase project
**`simks-partnership`** (ref `cmvmukexzmmagupbndmx`, region ap-southeast-1, Postgres 17),
honouring PRD D18 "one database, two systems". Realisasi must **never write SIMKS tables** and must
not create objects in SIMKS's `public` schema.

## What SIMKS actually has (discovered read-only, 2026-10-01)

| Realisasi needs (Schema §1.1) | SIMKS source | Notes |
|---|---|---|
| `units(id,name,parent_id,kind)` | `public.unit(id, nama, id_parent_unit, id_jenis_unit, is_active)` + `jenis_unit` (1 Unit Akademik, 2 Unit Pembantu) | kind: jenis 2 → `up`; jenis 1 with parent → `prodi`, else `faculty`. 76 rows. |
| `countries(code,name)` | `public.negara(id, kode, nama, is_domestic, …)` | **`kode` is ISO alpha-3** (`IDN`, `JPN`…); Realisasi uses alpha-2 (`ID`). Map alpha-3→alpha-2 in the adapter. Domestic = `is_domestic`. |
| `partners(id,name,country_code)` | `public.partner(id, nama, id_negara, is_international, id_merged_into, is_active)` | country via `negara`. |
| `documents(id, doc_number, title, kind, status, start_date, end_date, auto_renewed, predecessor_id, archived_reason, terminated_at)` | `public.dokumen_kerja_sama(no, id_proposal_dokumen, no_dokumen, tanggal_mulai, tanggal_berakhir, status, alasan_arsip, …)` ⋈ `public.proposal_dokumen(id, jenis_kerjasama MoU/MoA, id_dokumen_sebelumnya, …)` | id = `dokumen_kerja_sama.no`. status `Aktif`/`Akan Berakhir` → `active`, `Diarsipkan` → `archived`. `alasan_arsip` ∈ {null, `rejected`, `superseded_by_renewal`, `expired_without_renewal`}. Rejected docs have null dates. **`proposal_dokumen.id_dokumen_sebelumnya` points to the predecessor's *proposal* id** (e.g. proposal 92 → prev 87 = doc 28), so `predecessor_id` = the doc whose `id_proposal_dokumen` = prev. **No auto-renew concept** (all `sifat_periode_kerjasama` = 'Kedua Belah Pihak') → `auto_renewed=false`; no termination timestamp → `terminated_at=null`. |
| `document_partners(document_id, partner_id, is_lead)` | `public.partner_pengusul(id_partner, id_proposal_dokumen, is_lead)` | keyed by proposal → join through `dokumen_kerja_sama.id_proposal_dokumen`. |
| `document_scope_units(document_id, unit_id)` | `public.proposal_dokumen_unit(id_proposal_dokumen, id_unit)` | same join. |
| `profiles(id uuid, email, display_name, app_role, unit_id)` | `public.akun(id int, auth_user_id uuid, id_jabatan, email, role, is_active)` ⋈ `jabatan(id, nama, id_unit)` | Only 8/122 akun have `auth_user_id`. SIMKS roles are `admin/approver/user/user_staff` — **not** Realisasi roles. Realisasi keeps its own role/team assignment table keyed by akun id. Profile uuid = `coalesce(auth_user_id, md5('simks-akun:'||id)::uuid)` (stable). |

Real data: 39 `dokumen_kerja_sama` rows (13 rejected), renewal chains 28→33 and 29→34, dates
2024-08 … 2031; many docs started 2025-10-17, 2026-02-19, 2026-08-28, 2026-09-18+.
Extensions present: `pg_trgm` (schema `extensions`), `pgcrypto`, `pg_cron`. Roles `anon`,
`authenticated`, `service_role` exist. No `realisasi`/`mock_*` schemas yet.

## Final design (implemented 2026-10-01, proven locally; not yet deployed)

```
SIMKS (public, owned by SIM Kerjasama)          Realisasi
 unit, jenis_unit, negara, partner,     ──read──▶ kerjasama.*  (adapter views, owner rights)  ──▶ realisasi.* RPCs/views
 proposal_dokumen, dokumen_kerja_sama,             ▲ LEFT JOIN                                    mock_baak.*, mock_hr.*
 partner_pengusul, proposal_dokumen_unit,          │
 jabatan, akun                                     realisasi.account_roles, realisasi.document_overrides
```

### Schemas and ownership
| Schema | Created by | Contents |
|---|---|---|
| `public` | SIMKS | untouched. Realisasi creates, alters, grants, and writes **nothing** here. `scripts/db-test.sh` lint and `supabase/tests/70_simks_adapter.sql` enforce this. |
| `kerjasama` | `0001_kerjasama_adapter.sql` | `iso3166` (alpha-2 ↔ alpha-3, the full ISO list + XK, seeded in the migration) and 7 read-only views with the Schema §1.1 columns |
| `realisasi` | 0001–0017 | the application, plus `account_roles` and `document_overrides` |
| `mock_baak`, `mock_hr` | 0002 | mock registries (demo) |

### Adapter mapping (`kerjasama.*`)
| View | Columns (§1.1 first, then additive) | Mapping |
|---|---|---|
| `units` | id, name, parent_id, kind, is_active | `unit`. kind: `id_jenis_unit<>1` → `up`; an academic root with academic grandchildren → `up`; an academic unit with academic children → `faculty`; an academic leaf under an academic parent → `prodi`; any other academic leaf → `faculty`. `program` is never produced. |
| `countries` | code, name, alpha3, negara_id, is_domestic | `negara ⋈ iso3166 on alpha3 = upper(trim(kode))`, one row per alpha-2. An unmappable `kode` is left out. |
| `partners` | id, name, country_code, merged_into_id, is_active | `partner`. Country via `negara`/`iso3166`. With no mappable country, a domestic partner (`is_international=false`) gets `ID` and any other partner gets null. Merged/inactive partners are kept. |
| `documents` | id, doc_number, title, kind, status, start_date, end_date, auto_renewed, predecessor_id, archived_reason, terminated_at, proposal_id, simks_status | `dokumen_kerja_sama d ⋈ proposal_dokumen p`. id = `d.no`. doc_number = `no_dokumen`, or `Tanpa nomor #<no>` when it is null. title = the first line of `tujuan_kerjasama` (≤160 chars), else `<kind> <lead partner>`. kind = `jenis_kerjasama::text`. status: `alasan_arsip='rejected'` → `rejected`; `Aktif`/`Akan Berakhir` → `active`; `Diarsipkan` → `archived`; anything else → `in_process`. predecessor_id = the dokumen whose `id_proposal_dokumen = p.id_dokumen_sebelumnya` (a **proposal** id). archived_reason = `alasan_arsip` verbatim. auto_renewed/terminated_at come from `realisasi.document_overrides` (default false/null). The former stub's `parent_id` (MoA under MoU) is gone because SIMKS has no such link. |
| `document_partners` | document_id, partner_id, is_lead | `partner_pengusul` joined through `id_proposal_dokumen` |
| `document_scope_units` | document_id, unit_id | `proposal_dokumen_unit` joined through `id_proposal_dokumen` |
| `profiles` | id, email, display_name, app_role, unit_id, akun_id, auth_user_id | `realisasi.account_roles ⋈ akun ⟕ jabatan`. **Only accounts that have an `account_roles` row.** id = `coalesce(auth_user_id, md5('simks-akun:'||akun.id)::uuid)` (stable). display_name = `jabatan.nama`, else email. app_role = the `account_roles` role, or null (= no access) when `akun.is_active` is false. unit_id = `account_roles.unit_id`, else `jabatan.id_unit`. |

### Access model (decision)
The `kerjasama` views are plain views with `security_invoker=false`, owned by the migration owner (`postgres`, the owner of the SIMKS tables). They read SIMKS with the owner's rights, so SIMKS RLS does not filter them. `authenticated` gets `USAGE` on `kerjasama` and `SELECT` on the 7 views only. It gets nothing on any SIMKS table, on `iso3166`, or on `account_roles`/`document_overrides`. `anon` gets nothing.
- **Why views and not SECURITY DEFINER functions:** views stay inlinable. Predicates and joins push down into the SIMKS tables, which matters for the recursive chain walks. With 1,500 documents, a correlated-subquery version of `predecessor_id` made `_chain_map()` take 2.7 s; the join version takes 5 ms. Views are also read-only by construction (multi-table joins plus SELECT-only grants).
- **Cost:** the Supabase advisor reports "security definer view" for `kerjasama.*`. This is intended. `kerjasama` is not an exposed PostgREST schema; keep it out of *Exposed schemas*.
- **Assumption:** SIMKS tables are owned by `postgres` and do not use `FORCE ROW LEVEL SECURITY`. `db-deploy-supabase.sh` checks this after deploy: as `authenticated`, the view counts must equal the SIMKS row counts.

### Foreign keys → validation
Views cannot be FK targets, so every FK to the former `public.*` stubs was dropped. Each such column carries a `-- kerjasama.<view>.<col>` comment. What replaces them:
- RPCs already validate ids: `save_activity_draft` checks units, co-units, country and external-person countries (`VALIDATION_INVALID`) and documents via `documents_valid_between` (`R04_AGREEMENT_NOT_VALID`, which also rejects unknown, in-process and rejected documents). `create/update_known_activity` checks unit and country.
- The `activity_documents` BEFORE INSERT trigger raises SQLSTATE 23503 when the document is not in `kerjasama.documents`.
- Every `country_code` column in `realisasi` has `check (country_code ~ '^[A-Z]{2}$')`. Realisasi stays alpha-2 everywhere.
- `_require_uid()` requires `app_role is not null`, and `_notify()` skips accounts without access.

### Files
| Path | Applied where |
|---|---|
| `supabase/local/00_simks_stub.sql` | **local only**, by `db-reset.sh` before the migrations. It creates the roles, `auth.uid()`, and the SIMKS-shaped tables (same names/types; RLS on; no API grants). The enum is `public.jenis_kerjasama`, but the adapter only reads `::text`, so the real type name does not matter. |
| `supabase/migrations/0000…0017` | everywhere. 0000 now only creates extensions and **asserts** that the roles, `auth.uid()` and the SIMKS tables exist. |
| `supabase/seed/*.sql` | **local only**. `00_kerjasama.sql` writes the demo fixtures into the stub tables (proposal id = no + 1000) plus `account_roles`, `team_members` and `document_overrides` (903 auto-renewed, 119 terminated). |
| `supabase/seed-supabase/*.sql` | Supabase only, through `db-deploy-supabase.sh`. 01 config (reuses `seed/01_config.sql` and merges SIMKS `public.holidays` read-only; enables `demo_time_travel`), 02 mock BAAK/HR, 03 account roles + teams, 04 twelve demo activities on real documents 11, 15, 17, 19, 25, 28, 29, 33, 34, 36, 42, 44, 05 AY 2024/2025 in the calendar plus 50 history kegiatan (RL-xxxx-0201…0250, AY 2024/2025 to today) on real documents, freezing AY 2024/2025 and re-freezing any live system snapshot the history makes stale, 90 freeze AY 2025/2026. All idempotent. |
| `supabase/rehearsal/10_simks_snapshot.sql` | local rehearsal only. It approximates the live SIMKS data discovered on 2026-10-01: the 39 documents with real numbers, dates, status and renewal links, and the 21 key accounts, plus the live units that `05_activities_history.sql` uses. Scope units are guessed. |

### Accounts on Supabase (`seed-supabase/03_accounts.sql`)
| akun | email | Realisasi role | unit | teams | has auth user |
|---|---|---|---|---|---|
| 1 | kepala-kui@petra.ac.id | io_admin | (jabatan → 2) | partnership, mobility | yes |
| 11 | staff-partnership@petra.ac.id | io_staff | (2) | partnership | no → md5 uuid |
| 10 | head-partnership@petra.ac.id | io_staff | (2) | mobility | no → md5 uuid |
| 3 | dekan-sbm@petra.ac.id | submitter | 4 | — | yes |
| 4 | kaprodi-manajemen@petra.ac.id | submitter | 5 | — | yes |
| 9 | viewer@petra.ac.id | viewer | (1) | — | yes |
| 6 | rektor@petra.ac.id | viewer | (1) | — | yes |

The demo login (`DEMO_AUTH`, cookie = profile id) works for all of them. Accounts without a Supabase Auth user still get a stable uuid.

## Deploy status

- 2026-10-01: preflight on `simks-partnership` passed via the Supabase connector (read-only): the 10 SIMKS tables
  the adapter reads are owned by `postgres` with RLS on but **not forced**; `auth.uid()` exists; schemas
  `realisasi`, `kerjasama`, `mock_baak`, `mock_hr` are absent; existing cron jobs are `simks-sapu-sla` and
  `simks-sapu-kedaluarsa` (untouched). Local rehearsal (`--rehearse`) passes.
- 2026-10-01 23:4x UTC: a deploy through the Supabase MCP connector was started and **stopped part-way**: migrations
  0000–0006 and the first part of 0007 (`realisasi_0007a_*`) are applied, plus a placeholder
  `realisasi._apply_activity_payload`. The connector hangs on any statement containing DELETE/TRUNCATE (it asks for a
  confirmation that never reaches the user), even inside function bodies, so it cannot complete the install.
  Finish with **`scripts/db-deploy-supabase.sh --reset-realisasi`**: in one transaction it drops only Realisasi's own
  schemas (`realisasi`, `kerjasama`, `mock_baak`, `mock_hr`), its pg_cron job and its `realisasi_*` migration-history
  rows, then applies everything and verifies. SIM Kerjasama tables are untouched.
- **Not fully applied.** Waiting for the connection string in the environment variable **`SUPABASE_DB_URL`**
  (session pooler, port 5432). With it set, run steps 3–4 below as
  `DATABASE_URL="$SUPABASE_DB_URL" scripts/db-deploy-supabase.sh --check` and then `--reset-realisasi`
  (plain deploy refuses because of the partial install). Expected fingerprint (commit of this note):
  `functions 179 d1b4e9b966adc41af70a6574f2d29334`, `columns 380 c9ebd5632031b508bc93abbd7aecf942`,
  `policies 26 eeffda2ce3c17574a082ef903b081191`.

## Deploy status (2026-10-02)

Installed on `simks-partnership` via the SQL Editor (5 parts). Verified: 179 functions (identical to the tested build
once Windows CRLF line endings from the paste are ignored), 380 columns, 26 policies, 12 activities, 2 frozen snapshots,
7 accounts, 39/39 SIMKS documents visible, cron job `realisasi-daily-jobs`. As io_admin: role resolves, dashboard computes.
Remaining: Vercel `DATABASE_URL` (connector lacks permission to set env vars) and rotating the DB password.

**Revisi V.1 (not yet applied to `simks-partnership`).** The migrations were edited in place (agenda-based Jenis
Kegiatan, Inbound/Outbound, one kerja sama per kegiatan, Mobility-only verification, student conflicts, four period
cut-offs, International Awards). The live install above is the previous build, so the new one must be installed with a
**reset of Realisasi's own schemas** (`scripts/db-deploy-supabase.sh --reset-realisasi`, or the SQL Editor files below,
which start with the same reset). Realisasi demo data is re-seeded; SIM Kerjasama tables are only read. Rehearsed
locally; expected fingerprint `functions 163 84b8965fcf9d1961b66537daf939dc6c`, `columns 311
2d5642106c6972cb2891cd93b0e3bd35`, `policies 24 8945131cda9b8642deb73b5364f39d2e`.

## Easiest deploy: Supabase SQL Editor (no psql, no network setup)

1. Large pastes can get mangled by the browser (seen: `values;` at line 100). Prefer the five smaller files
   `supabase/deploy/part-1-of-5.sql` … `part-5-of-5.sql`: run them in order, each in a new query; after any failure
   start again from part 1. Copy each with GitHub's **Copy raw file** button. Or open `supabase/deploy/sim-realisasi-supabase.sql` (regenerate with `scripts/build-sql-bundle.sh` after changing
   migrations or seeds) and copy its whole content.
2. Supabase Dashboard → project **simks-partnership** → **SQL Editor** → New query → paste → **Run**. Confirm the
   "destructive operation" prompt: the only things dropped are Realisasi's own schemas from the partial install.
3. The result grid shows the fingerprint; it must read `functions 163 84b8965fcf9d1961b66537daf939dc6c`,
   `columns 311 2d5642106c6972cb2891cd93b0e3bd35`, `policies 24 8945131cda9b8642deb73b5364f39d2e` (Revisi V.1 build).

The file is one transaction (an error rolls everything back), is safe to run again, and equals
`scripts/db-deploy-supabase.sh --reset-realisasi`.

## Deploy steps (lead)
1. **Rehearse locally**:
   `DATABASE_URL=postgresql://postgres@localhost:54322/sim_realisasi_rehearsal scripts/db-deploy-supabase.sh --rehearse`
   This rebuilds the scratch DB from the stub + snapshot, applies migrations + seed-supabase in one transaction, verifies, and prints the accounts.
2. **Plan**: `scripts/db-deploy-supabase.sh --dry-run`.
3. **Preflight on Supabase (read-only)**: use the session pooler (5432) or the direct connection, not the transaction pooler.
   `DATABASE_URL='postgresql://postgres.cmvmukexzmmagupbndmx:<pw>@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres' scripts/db-deploy-supabase.sh --check`
   Every line must be `ok`/rows/`absent`, and akun 1, 3, 4, 6, 9, 10, 11 must resolve to the emails above.
4. **Deploy**: run the same command without a mode. It is one transaction; any error rolls everything back. Check the verify block: as authenticated, `documents=<dokumen_kerja_sama count>` with `my_role=io_admin`, then 7 accounts, `unmapped negara.kode: none`.
5. **Advisors**: expect "security definer view" for `kerjasama.*` (intended) and nothing new in `public`. Do not add `kerjasama`/`realisasi` to the exposed API schemas.
6. **App env** (Vercel): `DATABASE_URL` = session pooler URL (`prepare:false` is already set in `lib/db.ts`), `DEMO_AUTH` on for the demo.
7. **Re-seed later** (idempotent): `--seed-only`.
   **Rollback**: `drop schema realisasi, kerjasama, mock_baak, mock_hr cascade; select cron.unschedule('realisasi-daily-jobs');` SIMKS data is never touched.

Maintenance: grant or revoke Realisasi access with `insert/update/delete realisasi.account_roles` (+ `realisasi.team_members` for IO staff). Record an auto-renewing or early-terminated agreement in `realisasi.document_overrides`. A new SIMKS country code only needs a row in `kerjasama.iso3166` if it is not in ISO 3166-1. There is no UI or RPC for these yet; the DBA does them.
