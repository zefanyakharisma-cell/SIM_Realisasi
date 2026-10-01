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

## Target design

- New schema **`kerjasama`** = read-only adapter views with exactly the Schema §1.1 shapes
  (`kerjasama.units`, `countries`, `partners`, `documents`, `document_partners`,
  `document_scope_units`, `profiles`). Every Realisasi migration references `kerjasama.*`, never
  `public.*`. Foreign keys to SIMKS tables are dropped (views can't be FK targets); RPCs validate ids.
- `realisasi.account_roles(akun_id int pk, app_role, unit_id)` + `realisasi.team_members` keyed by
  profile uuid hold Realisasi's own authorisation for SIMKS accounts.
- Local dev/tests: `supabase/local/00_simks_stub.sql` creates the **SIMKS-shaped** tables
  (`public.unit`, `negara`, `partner`, `dokumen_kerja_sama`, `proposal_dokumen`, …) with the demo
  fixtures, so the same adapter is exercised locally. It is **never** applied to Supabase.
- Supabase seed: Realisasi config + mock BAAK/HR + role assignments for chosen SIMKS accounts +
  demo activities linked to **real** SIMKS documents (written only into `realisasi.*`).
- App connects with the project's Postgres connection string (`DATABASE_URL`, session pooler,
  `prepare:false`); `withUser` keeps `set local role authenticated` + `request.jwt.claims`.
