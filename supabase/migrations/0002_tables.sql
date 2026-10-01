-- 0002_tables: Schema §3/§4 with CONTRACTS §2.3 deltas. Extra indexes cover FKs and RLS/helper predicates.

-- 3.1 Configuration --------------------------------------------------------
create table realisasi.team_members (
  account_id uuid references public.profiles(id),
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
  updated_by uuid references public.profiles(id),
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

create table realisasi.holidays (
  day  date primary key,
  name text not null
);

create table realisasi.activity_types (
  id                         serial primary key,
  name                       text unique not null,
  direction                  realisasi.direction not null default 'none',
  counts_as_mobility         boolean not null default false,
  counts_for_s1              boolean not null default true,
  requires_mobility_review   boolean not null default false,
  is_active                  boolean not null default true,
  sort_order                 int default 0
);

create table realisasi.sdgs (
  id   smallint primary key check (id between 1 and 17),
  name text not null
);

-- 3.2 Activities -----------------------------------------------------------
create sequence realisasi.activity_code_seq;

create table realisasi.event_groups (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);
create index on realisasi.event_groups (created_by);

create table realisasi.activities (
  id                  uuid primary key default gen_random_uuid(),
  code                text unique not null
                      default 'RL-' || to_char(now(),'YYYY') || '-' || lpad(nextval('realisasi.activity_code_seq')::text,4,'0'),
  name                text not null,
  type_id             int not null references realisasi.activity_types(id),
  start_date          date not null,
  end_date            date not null,
  academic_year_id    int references realisasi.academic_years(id),
  semester_id         int references realisasi.semesters(id),
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
  partnership_since   timestamptz,
  mobility_since      timestamptz,
  rejection_reason    text,
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
create index on realisasi.activities (type_id);
create index on realisasi.activities (semester_id);
create index on realisasi.activities (academic_year_id);
create index on realisasi.activities (created_by);
create index activities_name_trgm on realisasi.activities using gin (lower(name) gin_trgm_ops);

create table realisasi.activity_units (
  activity_id  uuid references realisasi.activities(id),
  unit_id      int  references public.units(id),
  is_submitter boolean not null default false,
  primary key (activity_id, unit_id)
);
create index on realisasi.activity_units (unit_id, activity_id);

create table realisasi.activity_documents (
  activity_id           uuid references realisasi.activities(id),
  original_document_id  int  not null references public.documents(id),
  chain_id              int  not null,
  out_of_scope_warning  boolean not null default false,
  primary key (activity_id, original_document_id)
);
create index on realisasi.activity_documents (chain_id);
create index on realisasi.activity_documents (original_document_id);

create table realisasi.activity_partner_snapshot (
  id            bigserial primary key,
  activity_id   uuid not null references realisasi.activities(id),
  document_id   int  not null,
  partner_id    int  not null,
  partner_name  text not null,
  country_code  text not null,
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
  country_code text not null references public.countries(code),
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
  uploaded_by  uuid references public.profiles(id),
  uploaded_at  timestamptz default now(),
  check (storage_path is not null or url is not null)
);
create unique index one_current_ia_ir
  on realisasi.activity_files (activity_id, kind)
  where is_current and kind in ('ia','ir');
create index on realisasi.activity_files (activity_id, kind);
create index on realisasi.activity_files (storage_path);
create index on realisasi.activity_files (uploaded_by);

-- 3.3 Participants -----------------------------------------------------------
create table realisasi.participant_set_versions (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references realisasi.activities(id),
  version      int  not null,
  status       realisasi.pset_status not null default 'draft',
  submitted_by uuid references public.profiles(id),
  submitted_at timestamptz default null,
  reviewed_by  uuid references public.profiles(id),
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
  transcript_path     text,
  row_note            text,
  unique (set_version_id, nrp),
  check (section = 'internal' or home_institution is not null)
);
create index on realisasi.participant_students (nrp);
create index on realisasi.participant_students (transcript_path) where transcript_path is not null;

create table realisasi.participant_staff (
  id             bigserial primary key,
  set_version_id uuid not null references realisasi.participant_set_versions(id),
  employee_id    text not null,
  full_name      text not null,
  unit_name      text,
  row_note       text,
  unique (set_version_id, employee_id)
);

-- 3.4 Duplicates, logs, known activities, notifications ---------------------
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
create index on realisasi.duplicate_candidates (activity_b);
create index on realisasi.duplicate_candidates (status);

create table realisasi.activity_log (
  id          bigserial primary key,
  activity_id uuid not null references realisasi.activities(id),
  kind        realisasi.log_kind not null,
  track       realisasi.team,
  action      text not null,
  actor_id    uuid references public.profiles(id),
  note        text,
  diff        jsonb,
  in_frozen_period boolean not null default false,
  created_at  timestamptz default now()
);
create index on realisasi.activity_log (activity_id, created_at);
create index on realisasi.activity_log (activity_id, action, created_at);
create index on realisasi.activity_log (actor_id);
create index activity_log_frozen_idx on realisasi.activity_log (created_at) where in_frozen_period;

create table realisasi.known_activities (
  id                  bigserial primary key,
  title               text not null,
  activity_date       date not null,
  unit_id             int references public.units(id),
  partner_name        text,
  country_code        text references public.countries(code),
  is_international    boolean not null,
  source              realisasi.known_source not null,
  source_reference    text,
  notes               text,
  status              realisasi.known_status not null default 'unmatched',
  matched_activity_id uuid references realisasi.activities(id),
  nudged_at           timestamptz,
  created_by          uuid references public.profiles(id),
  created_at          timestamptz default now(),
  check ((status = 'matched') = (matched_activity_id is not null))
);
create index on realisasi.known_activities (activity_date);
create index on realisasi.known_activities (matched_activity_id);
create index on realisasi.known_activities (unit_id);
create index on realisasi.known_activities (created_by);
create index known_activities_intl_status_idx on realisasi.known_activities (status, activity_date) where is_international;

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
  actor_id    uuid references public.profiles(id),
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
  frozen_by        uuid references public.profiles(id),
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
  created_by uuid references public.profiles(id),
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
