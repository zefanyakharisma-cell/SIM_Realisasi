-- 0002_tables: Schema §3/§4 with CONTRACTS §2.3 deltas. Extra indexes cover FKs and RLS/helper predicates.
-- SIM Kerjasama ids (units, countries, documents, profiles) point at kerjasama.* adapter views, which cannot be FK
-- targets: the RPCs validate them instead (CONTRACTS "Contract amendments (SIMKS integration)").

-- 3.1 Configuration --------------------------------------------------------
create table realisasi.team_members (
  account_id uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  team       realisasi.team,
  primary key (account_id, team)
);

-- Deployment flags: written only by the DBA / seeds (no RPC writes them, no grant). See M9 in docs/reviews/database-review.md.
--   demo_time_travel: when enabled, settings.demo_today shifts today()/now_ts(). Absent or false = production (real clock).
create table realisasi.deployment_flags (
  key     text primary key,
  enabled boolean not null
);

create table realisasi.settings (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  updated_at timestamptz default now()
);

create table realisasi.academic_years (
  id         serial primary key,
  label      text unique not null,
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
  cutoff_date      date not null,
  unique (academic_year_id, term),
  check (cutoff_date >= end_date)
);

-- Counting rules per SIMKS agenda (Jenis Kegiatan = kerjasama.agendas, Revisi V.1). An agenda without a row, or with a
-- null mobility_category, is not a mobility activity: no participants required, verified on submit.
create table realisasi.agenda_rules (
  agenda_id         int primary key,  -- kerjasama.agendas.id (no FK: adapter view)
  mobility_category realisasi.mobility_category,
  counts_for_s1     boolean not null default true,
  updated_by        uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  updated_at        timestamptz default now()
);

create table realisasi.sdgs (
  id   smallint primary key check (id between 1 and 17),
  name text not null
);

-- 3.2 Activities -----------------------------------------------------------
create sequence realisasi.activity_code_seq;

create table realisasi.event_groups (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  created_at timestamptz default now()
);
create index on realisasi.event_groups (created_by);

create table realisasi.activities (
  id                  uuid primary key default gen_random_uuid(),
  code                text unique not null
                      default 'RL-' || to_char(now(),'YYYY') || '-' || lpad(nextval('realisasi.activity_code_seq')::text,4,'0'),
  name                text not null,
  agenda_id           int not null,  -- kerjasama.agendas.id (no FK: adapter view); rules in realisasi.agenda_rules
  direction           realisasi.direction not null,
  start_date          date not null,
  end_date            date not null,
  academic_year_id    int references realisasi.academic_years(id),
  semester_id         int references realisasi.semesters(id),
  mode                realisasi.activity_mode not null,
  venue               text,
  country_code        text check (country_code ~ '^[A-Z]{2}$'),  -- kerjasama.countries.code (no FK: adapter view)
  sks_recognized      numeric(4,1),
  description         text not null,
  submitter_unit_id   int not null,  -- kerjasama.units.id (no FK: adapter view)
  created_by          uuid not null,  -- kerjasama.profiles.id (no FK: adapter view)
  submitted_at        timestamptz,
  verified_at         timestamptz,
  status              realisasi.activity_status not null default 'draft',
  mobility_status     realisasi.track_status not null default 'not_required',
  mobility_since      timestamptz,  -- when the mobility track last changed (revision reminders)
  event_group_id      uuid not null references realisasi.event_groups(id),
  reporting_deadline  date,
  is_late             boolean not null default false,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  check (end_date >= start_date)
);
create index on realisasi.activities (status, start_date);
create index on realisasi.activities (event_group_id);
create index on realisasi.activities (submitter_unit_id);
create index on realisasi.activities (agenda_id);
create index on realisasi.activities (semester_id);
create index on realisasi.activities (academic_year_id);
create index on realisasi.activities (created_by);
create index activities_name_trgm on realisasi.activities using gin (lower(name) gin_trgm_ops);

create table realisasi.activity_units (
  activity_id  uuid references realisasi.activities(id),
  unit_id      int ,  -- kerjasama.units.id (no FK: adapter view)
  is_submitter boolean not null default false,
  primary key (activity_id, unit_id)
);
create index on realisasi.activity_units (unit_id, activity_id);

create table realisasi.activity_documents (
  activity_id           uuid references realisasi.activities(id),
  original_document_id  int  not null,  -- kerjasama.documents.id (no FK: adapter view)
  chain_id              int  not null,
  out_of_scope_warning  boolean not null default false,
  primary key (activity_id, original_document_id)
);
create unique index one_agreement_per_activity on realisasi.activity_documents (activity_id);  -- Revisi V.1 item 7
create index on realisasi.activity_documents (chain_id);
create index on realisasi.activity_documents (original_document_id);

create table realisasi.activity_partner_snapshot (
  id            bigserial primary key,
  activity_id   uuid not null references realisasi.activities(id),
  document_id   int  not null,
  partner_id    int  not null,
  partner_name  text not null,
  country_code  text not null check (country_code ~ '^[A-Z]{2}$'),  -- alpha-2 from kerjasama.partners
  captured_at   timestamptz default now()
);
create index on realisasi.activity_partner_snapshot (activity_id, document_id);

create table realisasi.activity_sdgs (
  activity_id uuid references realisasi.activities(id),
  sdg_id      smallint references realisasi.sdgs(id),
  primary key (activity_id, sdg_id)
);
create index on realisasi.activity_sdgs (sdg_id);

create table realisasi.activity_external_persons (
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  full_name    text not null,
  institution  text not null,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),  -- kerjasama.countries.code (no FK: adapter view)
  role         realisasi.person_role not null,
  notes        text
);
create index on realisasi.activity_external_persons (activity_id);
create index on realisasi.activity_external_persons (country_code);

create table realisasi.activity_files (
  id           bigserial primary key,
  activity_id  uuid not null references realisasi.activities(id),
  kind         realisasi.file_kind not null,
  version      int not null default 1,
  storage_path text,
  url          text,
  filename     text,
  size_bytes   int,
  mime         text,
  is_current   boolean not null default true,
  uploaded_by  uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  uploaded_at  timestamptz default now(),
  check (storage_path is not null or url is not null)
);
create unique index one_current_ia_ir
  on realisasi.activity_files (activity_id, kind)
  where is_current and kind in ('ia','ir','mobility_bundle');
create index on realisasi.activity_files (activity_id, kind);
create index on realisasi.activity_files (storage_path);
create index on realisasi.activity_files (uploaded_by);

-- 3.3 Participants -----------------------------------------------------------
create table realisasi.participant_set_versions (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references realisasi.activities(id),
  version      int  not null,
  status       realisasi.pset_status not null default 'draft',
  submitted_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  submitted_at timestamptz default null,
  reviewed_by  uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  reviewed_at  timestamptz,
  review_note  text,
  unique (activity_id, version)
);
create unique index one_approved_pset
  on realisasi.participant_set_versions (activity_id) where status = 'approved';
create unique index one_draft_pset
  on realisasi.participant_set_versions (activity_id) where status = 'draft';
create unique index one_pending_pset
  on realisasi.participant_set_versions (activity_id) where status = 'pending';
create index on realisasi.participant_set_versions (submitted_by);
create index on realisasi.participant_set_versions (reviewed_by);

create table realisasi.participant_students (
  id                  bigserial primary key,
  set_version_id      uuid not null references realisasi.participant_set_versions(id),
  section             realisasi.student_section not null,
  nrp                 text not null,
  full_name           text not null,
  faculty_name        text,
  prodi_name          text,
  home_institution    text,
  home_student_number text,
  home_country_code   text,
  unique (set_version_id, nrp),
  check (section = 'internal' or home_institution is not null)
);
create index on realisasi.participant_students (nrp);

create table realisasi.participant_staff (
  id             bigserial primary key,
  set_version_id uuid not null references realisasi.participant_set_versions(id),
  employee_id    text not null,
  full_name      text not null,
  unit_name      text,
  unique (set_version_id, employee_id)
);

-- 3.4 Duplicates, logs, known activities, notifications ---------------------
-- One student (NRP) claimed by activities of two different units with overlapping dates (Revisi V.1, rule 2.1).
-- Mobility picks the activity that keeps the student (kept_activity_id); the other one does not count them. While open,
-- the student counts for neither. The same unit claiming a student in two activities is never a conflict (rule 2.2).
create table realisasi.participant_conflicts (
  id               bigserial primary key,
  nrp              text not null,
  activity_a       uuid not null references realisasi.activities(id),
  activity_b       uuid not null references realisasi.activities(id),
  status           realisasi.conflict_status not null default 'open',
  kept_activity_id uuid references realisasi.activities(id),
  note             text,
  resolved_by      uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  resolved_at      timestamptz,
  created_at       timestamptz default now(),
  check (activity_a < activity_b),
  check ((status = 'resolved') = (kept_activity_id is not null)),
  check (kept_activity_id is null or kept_activity_id in (activity_a, activity_b)),
  unique (nrp, activity_a, activity_b)
);
create index on realisasi.participant_conflicts (activity_b);
create index on realisasi.participant_conflicts (status);
create index on realisasi.participant_conflicts (kept_activity_id);

create table realisasi.activity_log (
  id          bigserial primary key,
  activity_id uuid not null references realisasi.activities(id),
  kind        realisasi.log_kind not null,
  track       realisasi.team,
  action      text not null,
  actor_id    uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  note        text,
  diff        jsonb,
  in_frozen_period boolean not null default false,
  created_at  timestamptz default now()
);
create index on realisasi.activity_log (activity_id, created_at);
create index on realisasi.activity_log (activity_id, action, created_at);
create index on realisasi.activity_log (actor_id);
create index activity_log_frozen_idx on realisasi.activity_log (created_at) where in_frozen_period;

create table realisasi.notifications (
  id           bigserial primary key,
  recipient_id uuid not null,  -- kerjasama.profiles.id (no FK: adapter view)
  kind         text not null,
  title        text not null,
  body         text,
  link         text,
  read_at      timestamptz,
  created_at   timestamptz default now()
);
create index on realisasi.notifications (recipient_id, created_at desc);

create table realisasi.email_outbox (
  id         bigserial primary key,
  to_email   text not null,
  subject    text not null,
  body       text not null,
  created_at timestamptz default now(),
  sent_at    timestamptz
);

create table realisasi.export_log (
  id          bigserial primary key,
  actor_id    uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  export_kind text not null,
  filters     jsonb,
  row_count   int,
  contains_personal_data boolean not null,
  created_at  timestamptz default now()
);
create index on realisasi.export_log (actor_id);

-- 3.5 Snapshots ------------------------------------------------------------
create table realisasi.kpi_snapshots (
  id               uuid primary key default gen_random_uuid(),
  academic_year_id int not null references realisasi.academic_years(id),
  kind             realisasi.snapshot_kind not null,
  window_start     date not null,
  window_end       date not null,
  cutoff_date      date not null,
  values           jsonb not null,
  settings_used    jsonb not null,
  frozen_at        timestamptz not null default now(),
  frozen_by        uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  superseded_by    uuid references realisasi.kpi_snapshots(id) deferrable initially deferred,
  refreeze_reason  text
);
create unique index one_live_snapshot
  on realisasi.kpi_snapshots (academic_year_id, kind) where superseded_by is null;
create index on realisasi.kpi_snapshots (frozen_at);
create index on realisasi.kpi_snapshots (frozen_by);

create table realisasi.kpi_snapshot_items (
  snapshot_id     uuid references realisasi.kpi_snapshots(id),
  kpi_code        text not null,
  bucket          text not null,
  ref_type        text not null,
  ref_id          text not null,
  is_late_addition boolean not null default false,
  primary key (snapshot_id, kpi_code, bucket, ref_type, ref_id)
);

-- Storage emulation + job bookkeeping (CONTRACTS §2.3) ---------------------
create table realisasi.file_blobs (
  path       text primary key,
  bucket     text not null check (bucket in ('realisasi-files','realisasi-transcripts')),
  data       bytea not null,
  mime       text not null,
  size_bytes int  not null check (size_bytes <= 10485760),
  created_by uuid,  -- kerjasama.profiles.id (no FK: adapter view)
  created_at timestamptz not null default now(),
  check (split_part(path,'/',1) = bucket)
);
create table realisasi.job_marks (key text primary key, created_at timestamptz not null default now());

-- 4. Mock external systems ---------------------------------------------------
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
