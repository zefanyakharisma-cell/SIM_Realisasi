# SIM Realisasi — Schema
**Version:** 1.0 (Mockup) · Postgres (Supabase) · shares the database with SIM Kerjasama v2.0

---

## 1. Layout

| Schema | Owner | Contents |
|---|---|---|
| `public` | SIM Kerjasama | units, countries, partners, documents, accounts/profiles (read-only from Realisasi) |
| `realisasi` | SIM Realisasi | all tables below |
| `mock_baak` | Mockup only | dummy student registry |
| `mock_hr` | Mockup only | dummy employee registry |

> **Alignment note:** the `public.*` column names below are the minimum Realisasi depends on. Map them to the actual SIM Kerjasama v2.0 Schema names before build; only the views in §5 should touch `public` directly.

### 1.1 SIM Kerjasama columns Realisasi depends on
```text
public.units(id, name, parent_id, kind)                      -- kind: faculty | prodi | program | up
public.countries(code, name)                                 -- ISO-3166 alpha-2; 'ID' = Indonesia
public.partners(id, name, country_code)
public.documents(id, doc_number, title, kind, status, start_date, end_date,
                 auto_renewed, predecessor_id, archived_reason, terminated_at)
                                                             -- kind: MoU | MoA ; status: active | archived | in_process ...
public.document_partners(document_id, partner_id, is_lead)
public.document_scope_units(document_id, unit_id)            -- Lingkup Kerja Sama
public.profiles(id, email, display_name, app_role, unit_id)  -- app_role: submitter | io_staff | io_admin | viewer
```

---

## 2. Enums
```sql
create schema if not exists realisasi;

create type realisasi.activity_status   as enum ('draft','in_verification','revision_requested','verified','rejected');
create type realisasi.track_status      as enum ('not_required','pending','revision_requested','approved','rejected');
create type realisasi.direction         as enum ('inbound','outbound','none');
create type realisasi.activity_mode     as enum ('offline','online','hybrid');
create type realisasi.funding_source    as enum ('pcu','partner','government','participant','mixed','none');
create type realisasi.file_kind         as enum ('ia','ir','evidence');
create type realisasi.person_role       as enum ('speaker','visiting_lecturer','researcher','staff_visitor','other');
create type realisasi.student_section   as enum ('internal','inbound');
create type realisasi.pset_status       as enum ('pending','revision_requested','approved','superseded');
create type realisasi.known_source      as enum ('surat_tugas','news','faculty_report','loa_visa_letter','email','other');
create type realisasi.known_status      as enum ('unmatched','matched','dismissed');
create type realisasi.semester_term     as enum ('ganjil','genap');
create type realisasi.snapshot_kind     as enum ('ganjil_ytd','genap_full_year');
create type realisasi.dup_status        as enum ('open','linked','dismissed');
create type realisasi.log_kind          as enum ('verification','revision','update','system');
create type realisasi.team              as enum ('partnership','mobility');
```

---

## 3. Tables

### 3.1 Configuration
```sql
create table realisasi.team_members (
  account_id uuid references public.profiles(id),
  team       realisasi.team,
  primary key (account_id, team)
);

create table realisasi.settings (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz default now()
);
-- seed keys: grace_period_months=6, reporting_deadline_days=30,
-- sla_yellow_days=3, sla_red_days=5, revision_reminder_days=7, revision_escalate_days=14,
-- dup_date_window_days=3, dup_name_similarity=0.5, known_match_window_days=7

create table realisasi.academic_years (
  id         serial primary key,
  label      text unique not null,          -- '2026/2027'
  start_date date not null,
  end_date   date not null,
  check (end_date > start_date)
);

create table realisasi.semesters (
  id               serial primary key,
  academic_year_id int not null references realisasi.academic_years(id),
  term             realisasi.semester_term not null,
  start_date       date not null,
  end_date         date not null,
  cutoff_date      date not null,           -- default end_date + 30
  unique (academic_year_id, term),
  check (cutoff_date >= end_date)
);

create table realisasi.holidays (
  day  date primary key,
  name text not null
);

create table realisasi.activity_types (          -- Jenis Kegiatan master
  id                         serial primary key,
  name                       text unique not null,
  direction                  realisasi.direction not null default 'none',
  counts_as_mobility         boolean not null default false,  -- KPI 1.1
  counts_for_s1              boolean not null default true,   -- KPI 1.19.S1
  requires_mobility_review   boolean not null default false,
  is_active                  boolean not null default true,
  sort_order                 int default 0
);

create table realisasi.sdgs (
  id   smallint primary key check (id between 1 and 17),
  name text not null
);
```

### 3.2 Activities
```sql
create sequence realisasi.activity_code_seq;

create table realisasi.event_groups (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table realisasi.activities (
  id                  uuid primary key default gen_random_uuid(),
  code                text unique not null
                      default 'RL-' || to_char(now(),'YYYY') || '-' || lpad(nextval('realisasi.activity_code_seq')::text,4,'0'),
  name                text not null,
  type_id             int not null references realisasi.activity_types(id),
  start_date          date not null,
  end_date            date not null,
  academic_year_id    int references realisasi.academic_years(id),   -- derived (trigger)
  semester_id         int references realisasi.semesters(id),        -- derived (trigger)
  mode                realisasi.activity_mode not null,
  venue               text,
  city                text,
  country_code        text references public.countries(code),
  sks_recognized      numeric(4,1),
  funding_source      realisasi.funding_source,
  description         text not null,
  submitter_unit_id   int not null references public.units(id),
  created_by          uuid not null references public.profiles(id),
  submitted_at        timestamptz,
  verified_at         timestamptz,
  status              realisasi.activity_status not null default 'draft',
  partnership_status  realisasi.track_status not null default 'pending',
  mobility_status     realisasi.track_status not null default 'not_required',
  rejection_reason    text,
  event_group_id      uuid not null references realisasi.event_groups(id),
  reporting_deadline  date,                                          -- end_date + setting
  is_late             boolean not null default false,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  check (end_date >= start_date)
);
create index on realisasi.activities (status, start_date);
create index on realisasi.activities (event_group_id);
create index on realisasi.activities (submitter_unit_id);

create table realisasi.activity_units (
  activity_id  uuid references realisasi.activities(id),
  unit_id      int  references public.units(id),
  is_submitter boolean not null default false,
  primary key (activity_id, unit_id)
);

create table realisasi.activity_documents (
  activity_id           uuid references realisasi.activities(id),
  original_document_id  int  not null references public.documents(id),  -- never changes
  chain_id              int  not null,                                  -- root of renewal chain
  out_of_scope_warning  boolean not null default false,                 -- unit not in Lingkup Kerja Sama
  primary key (activity_id, original_document_id)
);
-- current_document_id is resolved by view realisasi.v_activity_documents (§5), never stored.

create table realisasi.activity_partner_snapshot (
  id            bigserial primary key,
  activity_id   uuid not null references realisasi.activities(id),
  document_id   int  not null,
  partner_id    int  not null,
  partner_name  text not null,
  country_code  text not null,
  captured_at   timestamptz default now()
);

create table realisasi.activity_sdgs (
  activity_id uuid references realisasi.activities(id),
  sdg_id      smallint references realisasi.sdgs(id),
  primary key (activity_id, sdg_id)
);

create table realisasi.activity_external_persons (   -- Pembicara / Dosen Asing / Tamu
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  full_name    text not null,
  institution  text not null,
  country_code text not null references public.countries(code),
  role         realisasi.person_role not null,
  notes        text
);

create table realisasi.activity_files (
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  kind         realisasi.file_kind not null,
  version      int not null default 1,
  storage_path text,                 -- null when evidence is a link
  url          text,                 -- evidence link
  filename     text,
  size_bytes   int,
  mime         text,
  is_current   boolean not null default true,
  uploaded_by  uuid references public.profiles(id),
  uploaded_at  timestamptz default now(),
  check (storage_path is not null or url is not null)
);
create unique index one_current_ia_ir
  on realisasi.activity_files (activity_id, kind)
  where is_current and kind in ('ia','ir');
```

### 3.3 Participants (versioned)
```sql
create table realisasi.participant_set_versions (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references realisasi.activities(id),
  version      int  not null,
  status       realisasi.pset_status not null default 'pending',
  submitted_by uuid references public.profiles(id),
  submitted_at timestamptz default now(),
  reviewed_by  uuid references public.profiles(id),
  reviewed_at  timestamptz,
  review_note  text,
  unique (activity_id, version)
);
create unique index one_approved_pset
  on realisasi.participant_set_versions (activity_id) where status = 'approved';

create table realisasi.participant_students (
  id                  bigserial primary key,
  set_version_id      uuid not null references realisasi.participant_set_versions(id),
  section             realisasi.student_section not null,   -- internal = PETRA student, inbound = external student with PETRA NRP
  nrp                 text not null,
  full_name           text not null,      -- snapshot from lookup
  faculty_name        text,
  prodi_name          text,
  home_institution    text,               -- inbound only
  home_student_number text,               -- inbound only
  home_country_code   text,               -- inbound only
  transcript_path     text,               -- inbound only (required)
  row_note            text,               -- Mobility's per-row revision note
  unique (set_version_id, nrp),
  check (section = 'internal' or (home_institution is not null and transcript_path is not null))
);

create table realisasi.participant_staff (
  id             bigserial primary key,
  set_version_id uuid not null references realisasi.participant_set_versions(id),
  employee_id    text not null,
  full_name      text not null,
  unit_name      text,
  row_note       text,
  unique (set_version_id, employee_id)
);
```

### 3.4 Duplicates, logs, known activities, notifications
```sql
create table realisasi.duplicate_candidates (
  id          bigserial primary key,
  activity_a  uuid not null references realisasi.activities(id),
  activity_b  uuid not null references realisasi.activities(id),
  score       numeric(3,2) not null,
  status      realisasi.dup_status not null default 'open',
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  check (activity_a < activity_b),
  unique (activity_a, activity_b)
);

create table realisasi.activity_log (
  id          bigserial primary key,
  activity_id uuid not null references realisasi.activities(id),
  kind        realisasi.log_kind not null,
  track       realisasi.team,                 -- null for unit/system actions
  action      text not null,                  -- submit | approve | request_revision | resubmit | reject | edit | link_duplicate | ...
  actor_id    uuid references public.profiles(id),
  note        text,
  diff        jsonb,                          -- {field: [old, new]} for update logs
  in_frozen_period boolean not null default false,
  created_at  timestamptz default now()
);
create index on realisasi.activity_log (activity_id, created_at);

create table realisasi.known_activities (
  id                  bigserial primary key,
  title               text not null,
  activity_date       date not null,
  unit_id             int references public.units(id),
  partner_name        text,
  country_code        text references public.countries(code),
  is_international    boolean not null,
  source              realisasi.known_source not null,
  source_reference    text,                   -- doc number or link
  notes               text,
  status              realisasi.known_status not null default 'unmatched',
  matched_activity_id uuid references realisasi.activities(id),
  nudged_at           timestamptz,
  created_by          uuid references public.profiles(id),
  created_at          timestamptz default now(),
  check ((status = 'matched') = (matched_activity_id is not null))
);

create table realisasi.notifications (
  id           bigserial primary key,
  recipient_id uuid not null references public.profiles(id),
  kind         text not null,
  title        text not null,
  body         text,
  link         text,
  read_at      timestamptz,
  created_at   timestamptz default now()
);

create table realisasi.email_outbox (           -- mockup: logged, not sent
  id         bigserial primary key,
  to_email   text not null,
  subject    text not null,
  body       text not null,
  created_at timestamptz default now(),
  sent_at    timestamptz
);

create table realisasi.export_log (             -- UU PDP audit for exports
  id          bigserial primary key,
  actor_id    uuid references public.profiles(id),
  export_kind text not null,
  filters     jsonb,
  row_count   int,
  contains_personal_data boolean not null,
  created_at  timestamptz default now()
);
```

### 3.5 Snapshots
```sql
create table realisasi.kpi_snapshots (
  id               uuid primary key default gen_random_uuid(),
  academic_year_id int not null references realisasi.academic_years(id),
  kind             realisasi.snapshot_kind not null,
  window_start     date not null,         -- academic year start
  window_end       date not null,         -- semester end (Ganjil) or AY end (Genap)
  cutoff_date      date not null,
  values           jsonb not null,        -- {kpi_1_1:{inbound,outbound,by_semester}, kpi_1_19_s1:{...}, ...}
  settings_used    jsonb not null,
  frozen_at        timestamptz not null default now(),
  frozen_by        uuid references public.profiles(id),   -- null = scheduled job
  superseded_by    uuid references realisasi.kpi_snapshots(id),
  refreeze_reason  text
);
create unique index one_live_snapshot
  on realisasi.kpi_snapshots (academic_year_id, kind) where superseded_by is null;

create table realisasi.kpi_snapshot_items (
  snapshot_id     uuid references realisasi.kpi_snapshots(id),
  kpi_code        text not null,          -- '1.1' | '1.19.S1' | '1.19.24' | '1.19.S8'
  bucket          text not null,          -- e.g. 'outbound', 'inbound', 'numerator', 'denominator', 'grace_excluded', 'unmatched_known'
  ref_type        text not null,          -- 'activity' | 'participant' | 'chain' | 'known_activity'
  ref_id          text not null,
  is_late_addition boolean not null default false,
  primary key (snapshot_id, kpi_code, bucket, ref_type, ref_id)
);
```

---

## 4. Mock external systems
```sql
create schema if not exists mock_baak;
create schema if not exists mock_hr;

create table mock_baak.students (
  nrp             text primary key,
  full_name       text not null,
  faculty_code    char(1) not null,
  faculty_name    text not null,
  prodi_name      text not null,
  category        text not null check (category in ('regular','inbound_exchange')),
  home_institution text,
  home_country_code text,
  intake_year     int not null,
  status          text not null check (status in ('active','graduated','inactive'))
);

create table mock_hr.employees (
  employee_id text primary key,
  full_name   text not null,
  unit_name   text not null,
  position    text,
  status      text not null check (status in ('active','inactive'))
);

-- API boundary: the app only calls these RPCs, never the tables.
create function realisasi.lookup_students(p_nrps text[])
returns setof mock_baak.students language sql stable security definer as $$
  select * from mock_baak.students where nrp = any(p_nrps);
$$;

create function realisasi.lookup_employees(p_ids text[])
returns setof mock_hr.employees language sql stable security definer as $$
  select * from mock_hr.employees where employee_id = any(p_ids);
$$;
```

### 4.1 Randomized identifier formats (mockup only)
| ID | Format | Example |
|---|---|---|
| PETRA student NRP | `{faculty letter A–H}{2-digit prodi}{2-digit intake year}{4-digit seq}` | `D31240187` |
| Inbound exchange NRP | `X{2-digit term code}{2-digit year}{4-digit seq}` | `X01260012` |
| Employee ID | `PG{6 digits}` | `PG204517` |

---

## 5. Views & functions

### 5.1 Renewal chains & document resolution
```sql
-- root of a renewal chain
create function realisasi.chain_root(p_doc int) returns int language sql stable as $$
  with recursive up as (
    select id, predecessor_id from public.documents where id = p_doc
    union all
    select d.id, d.predecessor_id from public.documents d join up on d.id = up.predecessor_id
  )
  select id from up where predecessor_id is null limit 1;
$$;

-- latest document in a chain (current)
create function realisasi.chain_current(p_doc int) returns int language sql stable as $$
  with recursive down as (
    select id, 0 as depth from public.documents where id = p_doc
    union all
    select d.id, down.depth + 1 from public.documents d join down on d.predecessor_id = down.id
  )
  select id from down order by depth desc limit 1;
$$;

create view realisasi.v_activity_documents as
select ad.*, realisasi.chain_current(ad.original_document_id) as current_document_id
from realisasi.activity_documents ad;

-- one row per chain with effective window
create view realisasi.v_chains as
select realisasi.chain_root(d.id)                         as chain_id,
       min(d.start_date)                                  as chain_start,
       max(coalesce(d.terminated_at::date, d.end_date))   as chain_end,      -- ignored when auto_renewed
       bool_or(d.auto_renewed)                            as auto_renewed,
       bool_or(exists (select 1 from public.document_partners dp
                       join public.partners p on p.id = dp.partner_id
                       where dp.document_id = d.id and p.country_code <> 'ID')) as is_international
from public.documents d
where d.start_date is not null
  and coalesce(d.archived_reason,'') <> 'rejected'
group by 1;
```

### 5.2 KPI functions (window = [p_from, p_to], cutoff for grace)
```sql
-- KPI 1.1  (university level: dedupe by event group)
create function realisasi.kpi_1_1(p_from date, p_to date)
returns table(direction realisasi.direction, students bigint) language sql stable as $$
  select t.direction, count(distinct (s.nrp, a.event_group_id))
  from realisasi.activities a
  join realisasi.activity_types t            on t.id = a.type_id and t.counts_as_mobility
  join realisasi.participant_set_versions v  on v.activity_id = a.id and v.status = 'approved'
  join realisasi.participant_students s      on s.set_version_id = v.id
       and ((t.direction = 'outbound' and s.section = 'internal')
         or (t.direction = 'inbound'  and s.section = 'inbound'))
  where a.status = 'verified' and a.start_date between p_from and p_to
  group by t.direction;
$$;
-- unit level: same query grouped by activity_units.unit_id and counting distinct (s.nrp, a.id)

-- KPI 1.19.S1
create function realisasi.kpi_1_19_s1(p_from date, p_to date)
returns bigint language sql stable as $$
  select count(distinct a.event_group_id)
  from realisasi.activities a
  join realisasi.activity_types t on t.id = a.type_id and t.counts_for_s1
  where a.status = 'verified' and a.start_date between p_from and p_to
    and exists (select 1 from realisasi.activity_partner_snapshot ps
                where ps.activity_id = a.id and ps.country_code <> 'ID');
$$;

-- KPI 1.19.24
create function realisasi.kpi_1_19_24(p_ay_start date, p_cutoff date, p_grace_months int)
returns table(scope text, numerator bigint, denominator bigint, grace_excluded bigint)
language sql stable as $$
  with active_chains as (
    select c.* from realisasi.v_chains c
    where c.chain_start <= p_cutoff
      and (c.auto_renewed or c.chain_end >= p_ay_start)
  ),
  classified as (
    select ac.*,
           (not ac.auto_renewed and ac.chain_start > p_cutoff - make_interval(months => p_grace_months)) as in_grace,
           exists (select 1 from realisasi.activity_documents ad
                   join realisasi.activities a on a.id = ad.activity_id
                   where ad.chain_id = ac.chain_id and a.status = 'verified'
                     and a.start_date between p_ay_start and p_cutoff) as realized
    from active_chains ac
  )
  select s.scope,
         count(*) filter (where not in_grace and realized),
         count(*) filter (where not in_grace),
         count(*) filter (where in_grace)
  from classified
  cross join lateral (values ('all'), (case when is_international then 'international' else 'domestic' end)) s(scope)
  group by s.scope;
$$;

-- KPI 1.19.S8
create function realisasi.kpi_1_19_s8(p_from date, p_to date)
returns table(reported bigint, unmatched_known bigint, pct numeric) language sql stable as $$
  with r as (
    select count(distinct a.event_group_id) n
    from realisasi.activities a
    where a.status = 'verified' and a.start_date between p_from and p_to
      and exists (select 1 from realisasi.activity_partner_snapshot ps
                  where ps.activity_id = a.id and ps.country_code <> 'ID')
  ), k as (
    select count(*) n from realisasi.known_activities
    where status = 'unmatched' and is_international and activity_date between p_from and p_to
  )
  select r.n, k.n, round(100.0 * r.n / nullif(r.n + k.n, 0), 1) from r, k;
$$;
```

### 5.3 Triggers (behaviour, implemented in SQL)
| Trigger | On | Does |
|---|---|---|
| `derive_period` | activities insert/update of `start_date` | sets `academic_year_id`, `semester_id` from calendar; rejects dates outside any configured year |
| `derive_deadline` | activities insert/update of `end_date` | `reporting_deadline = end_date + reporting_deadline_days`; `is_late = submitted_at::date > reporting_deadline` |
| `derive_overall_status` | activities update of track statuses | applies Rules R-25 |
| `snapshot_partners` | activity_documents insert | writes `activity_partner_snapshot` rows; sets `chain_id = chain_root(original_document_id)` |
| `supersede_pset` | participant_set_versions approve | previous approved → `superseded` |
| `log_changes` | activities/related updates after verification | writes `activity_log` kind `update` with diff; sets `in_frozen_period` |
| `touch_updated_at` | all mutable tables | `updated_at = now()` |

---

## 6. Row-level security (summary)
| Table group | submitter | io partnership | io mobility | io_admin | viewer |
|---|---|---|---|---|---|
| activities, units, documents, sdgs, external persons, files (IA/IR/evidence) | own unit R/W (draft, revision) | R/W | R | R/W | R (verified only) |
| participant_* + transcripts | own unit R/W (draft, revision) | count only | R/W | R/W | none |
| known_activities | none | R/W | R | R/W | none |
| settings, calendar, activity_types | R | R | R | R/W | R |
| kpi_snapshots(_items) | own unit (via views) | R | R | R/W | R |
| activity_log | own activities R | R | R | R | none |

Unit scope = `activity_units.unit_id = profiles.unit_id` (incl. co-units, read-only for co-units).

---

## 7. Seed data (mockup)

### 7.1 Accounts (role switcher)
| Email | app_role | team | unit |
|---|---|---|---|
| kepala.io@demo.petra.ac.id | io_admin | partnership + mobility | IO |
| io.partnership@demo.petra.ac.id | io_staff | partnership | IO |
| io.mobility@demo.petra.ac.id | io_staff | mobility | IO |
| ua-fti@demo.petra.ac.id | submitter | — | Fakultas Teknologi Industri |
| ua-fbe@demo.petra.ac.id | submitter | — | Fakultas Bisnis & Ekonomi |
| kaprodi-informatika@demo.petra.ac.id | submitter | — | Prodi Informatika |
| ua-fsd@demo.petra.ac.id | submitter | — | Fakultas Seni & Desain |
| rektorat@demo.petra.ac.id | viewer | — | Rektorat |

### 7.2 Calendar
- 2025/2026: Ganjil 2025-08-01 → 2026-01-31 (cutoff 2026-03-02, frozen); Genap 2026-02-01 → 2026-07-31 (cutoff 2026-08-30, frozen)
- 2026/2027: Ganjil 2026-08-01 → 2027-01-31 (cutoff 2027-03-02); Genap 2027-02-01 → 2027-07-31 (cutoff 2027-08-30)

### 7.3 Jenis Kegiatan
| Name | direction | mobility | S1 | mobility review |
|---|---|---|---|---|
| Student Outbound Mobility | outbound | ✓ | ✓ | ✓ |
| Student Inbound Mobility | inbound | ✓ | ✓ | ✓ |
| Staff Outbound Mobility | none | — | ✓ | ✓ |
| Visiting Lecturer / Guest Lecture | none | — | ✓ | — |
| Joint Research | none | — | ✓ | — |
| Joint Seminar / Conference | none | — | ✓ | — |
| Summer / Winter Program (Outbound) | outbound | ✓ | ✓ | ✓ |
| Community Service (Joint) | none | — | ✓ | — |
| Joint Publication | none | — | ✓ | — |

### 7.4 Registries
- `mock_baak.students`: 60 rows — 45 regular across faculties A–H, 15 `inbound_exchange` (home institutions in JP, KR, TW, DE, NL, AU, MY, TH, PH); 3 graduated, 2 inactive (to test lookup warnings).
- `mock_hr.employees`: 25 rows, 2 inactive.
- Names generated randomly (Indonesian names for regular/staff; locale-appropriate names for inbound).

### 7.5 Activities (≈30) — required scenarios
| # | Scenario | Exercises |
|---|---|---|
| S-01…S-12 | Normal verified activities across both years, 6 countries, domestic + international | baseline KPIs |
| S-13/S-14 | Same summer program submitted by FTI and Prodi Informatika, linked as one event group | dedupe vs unit double-count |
| S-15 | One student in two different outbound events | per-person-per-event |
| S-16 | Mobility revision v1 → v2 approved, Partnership already approved | dual-track independence |
| S-17 | Partnership revision on wrong IA file | Detail/File revision |
| S-18 | Rejected (duplicate) | terminal rejection |
| S-19 | Ganjil 2025/2026 activity verified after Ganjil freeze | late addition |
| S-20 | Activity on a document later renewed | chain counting, original vs current doc |
| S-21 | Activity linked to two agreements (multi-partner) | multi-document |
| S-22 | Activity where unit is outside Lingkup Kerja Sama | scope warning |
| S-23/S-24 | Draft past reporting deadline; late submission | deadline flags |
| S-25…S-30 | In-verification items with yellow/red SLA | SLA chips & reminders |
- Documents (from SIM Kerjasama seed or added): include one signed 3 months before the 2026/2027 Ganjil cutoff (grace-excluded), one auto-renewed with no activity, one renewed mid-year with activities on both sides.
- Known Activities: 8 entries — 5 matched, 2 unmatched international, 1 dismissed.
