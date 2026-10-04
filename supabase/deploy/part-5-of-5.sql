-- SIM Realisasi Supabase install, PART 5 OF 5 (commit ab83e5c).
-- Run parts 1..5 in order in Supabase Dashboard -> SQL Editor. If any part fails, start again from part 1.
begin;

-- >>> supabase/migrations/0015_jobs.sql
-- 0015_jobs: daily jobs (CONTRACTS §5.1). "Once" semantics via job_marks.

create function realisasi._mark_once(p_key text) returns boolean
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
begin
  insert into realisasi.job_marks (key, created_at) values (p_key, realisasi.now_ts()) on conflict (key) do nothing;
  return found;
end $$;

create function realisasi.run_daily_jobs() returns jsonb
language plpgsql security definer set search_path = realisasi, extensions, public, pg_temp as $$
declare
  v_today date := realisasi.today();
  v_rem int := 0; v_dl int := 0; v_frozen jsonb := '[]'::jsonb;
  r record; v_days int; v_since timestamptz; v_tag text; v_kind text;
  v_n int; v_id uuid; v_epoch bigint;
begin
  -- system caller (pg_cron/psql) or io_admin; an `authenticated` session with empty claims is refused (M4)
  if not realisasi._is_system_caller() then perform realisasi._require_admin(); end if;

  -- L8: SIM Kerjasama may re-parent documents; refresh the stored chain id of agreement links
  update realisasi.activity_documents ad set chain_id = m.root_id
    from realisasi._chain_map() m
   where m.doc_id = ad.original_document_id and ad.chain_id is distinct from m.root_id;

  -- Unit revision reminder (R-61). Revisi V.1: no SLA tracking and no escalation; just a reminder to the unit.
  for r in select a.* from realisasi.activities a where a.mobility_status = 'revision_requested' order by a.code loop
    v_since := r.mobility_since;
    v_days := v_today - (v_since at time zone 'Asia/Jakarta')::date;
    v_epoch := extract(epoch from v_since)::bigint;
    if v_days >= realisasi.setting_int('revision_reminder_days')
       and realisasi._mark_once(format('rev_remind:%s:mobility:%s', r.id, v_epoch)) then
      perform realisasi._notify_unit(r.submitter_unit_id, 'revision_reminder', 'Pengingat revisi: ' || r.code,
        format('Revisi kegiatan "%s" belum diajukan ulang (%s hari).', r.name, v_days), '/realisasi/kegiatan/' || r.id);
      v_rem := v_rem + 1;
    end if;
  end loop;

  -- Reporting-deadline reminders for drafts (R-62): one notification per run for the most advanced new tag
  for r in select * from realisasi.activities where status = 'draft' and reporting_deadline is not null order by code loop
    v_tag := null; v_kind := null;
    if v_today >= r.reporting_deadline - realisasi.setting_int('deadline_reminder_before_days')
       and realisasi._mark_once(format('deadline:%s:h7', r.id)) then v_tag := 'h7'; v_kind := 'deadline_h7'; end if;
    if v_today >= r.reporting_deadline and realisasi._mark_once(format('deadline:%s:h0', r.id)) then
      v_tag := 'h0'; v_kind := 'deadline_h0';
    end if;
    v_n := (v_today - r.reporting_deadline) / 7;
    if v_n >= 1 and realisasi._mark_once(format('deadline:%s:w%s', r.id, v_n)) then v_tag := 'w' || v_n; v_kind := 'deadline_weekly'; end if;
    if v_kind is not null then
      perform realisasi._notify_unit(r.submitter_unit_id, v_kind,
        format('Batas pelaporan %s: %s', realisasi._fmt_date(r.reporting_deadline), r.code),
        format('Draf kegiatan "%s" harus diajukan paling lambat %s.', r.name, realisasi._fmt_date(r.reporting_deadline)),
        '/realisasi/kegiatan/baru?draft=' || r.id);
      v_dl := v_dl + 1;
    end if;
  end loop;

  -- Semester freezes (R-55)
  for r in select s.*, ay.label as ay_label,
                  case when s.term = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end::realisasi.snapshot_kind as kind
             from realisasi.semesters s join realisasi.academic_years ay on ay.id = s.academic_year_id
            where s.cutoff_date <= v_today
              and not exists (select 1 from realisasi.kpi_snapshots k where k.academic_year_id = s.academic_year_id
                                and k.superseded_by is null
                                and k.kind = case when s.term = 'ganjil' then 'ganjil_ytd' else 'genap_full_year' end::realisasi.snapshot_kind)
            order by s.cutoff_date loop
    v_id := realisasi._freeze(r.academic_year_id, r.kind,
              least(realisasi.now_ts(), (r.cutoff_date + time '01:00') at time zone 'Asia/Jakarta'), null, null, null);
    v_frozen := v_frozen || jsonb_build_object('snapshot_id', v_id, 'ay_label', r.ay_label, 'kind', r.kind);
  end loop;

  return jsonb_build_object('today', v_today, 'revision_reminders', v_rem,
                            'deadline_reminders', v_dl, 'frozen', v_frozen);
end $$;

-- >>> supabase/migrations/0016_grants.sql
-- 0016_grants: least privilege. Reads via RLS-protected selects; writes only via definer RPCs.
revoke all on all tables in schema realisasi, mock_baak, mock_hr from public, anon, authenticated;
revoke all on all sequences in schema realisasi from public, anon, authenticated;
revoke execute on all functions in schema realisasi from public;
revoke all on schema mock_baak, mock_hr from public, anon, authenticated;
alter default privileges in schema realisasi revoke execute on functions from public;

grant usage on schema realisasi to authenticated;

grant select on
  realisasi.team_members, realisasi.settings, realisasi.academic_years, realisasi.semesters,
  realisasi.agenda_rules, realisasi.sdgs, realisasi.event_groups, realisasi.activities, realisasi.activity_units,
  realisasi.activity_documents, realisasi.activity_partner_snapshot, realisasi.activity_sdgs,
  realisasi.activity_external_persons, realisasi.activity_files, realisasi.participant_set_versions,
  realisasi.participant_students, realisasi.participant_staff, realisasi.participant_conflicts, realisasi.activity_log,
  realisasi.notifications, realisasi.email_outbox, realisasi.export_log,
  realisasi.kpi_snapshots, realisasi.kpi_snapshot_items
  to authenticated;
grant select on realisasi.v_activity_documents, realisasi.v_chains, realisasi.v_activity_list to authenticated;

-- Helpers called by RLS policies and security_invoker views
grant execute on function
  realisasi.today(), realisasi.now_ts(), realisasi.setting_int(text), realisasi.setting_num(text), realisasi.settings_json(),
  realisasi.chain_root(int), realisasi.chain_current(int), realisasi.semester_label(int),
  realisasi.my_role(), realisasi.my_unit(), realisasi.in_team(realisasi.team), realisasi.is_io(),
  realisasi.can_view_activity(uuid), realisasi.can_view_participants(uuid),
  realisasi.in_frozen_period(uuid), realisasi.is_late_addition(uuid),
  realisasi.activity_open_conflicts(uuid), realisasi.activity_participant_total(uuid),
  realisasi.agenda_category(int), realisasi.agenda_is_mobility(int),
  realisasi.demo_time_travel_enabled(),
  realisasi.my_activity_ids(), realisasi.visible_activity_ids(), realisasi.my_pset_ids(),
  realisasi.sees_participant_identifiers()
  to authenticated;

-- RPC catalogue (CONTRACTS §3)
grant execute on function
  realisasi.lookup_students(text[]), realisasi.lookup_employees(text[]),
  realisasi.documents_valid_between(date, date, int),
  realisasi.save_activity_draft(uuid, jsonb), realisasi.delete_draft(uuid), realisasi.ensure_participant_draft(uuid),
  realisasi.save_participants(uuid, jsonb, jsonb), realisasi.submission_checklist(uuid), realisasi.submit_activity(uuid),
  realisasi.can_read_file(text), realisasi.storage_put(text, text, bytea), realisasi.storage_get(text),
  realisasi.register_activity_file(uuid, realisasi.file_kind, text, text, int, text),
  realisasi.add_evidence_link(uuid, text, text), realisasi.remove_activity_file(bigint),
  realisasi.mobility_approve(uuid, text),
  realisasi.mobility_request_revision(uuid, text), realisasi.edit_verified_activity(uuid, jsonb, text),
  realisasi.commit_participant_edit(uuid, text),
  realisasi.conflict_list(uuid, text), realisasi.resolve_conflict(bigint, uuid, text),
  realisasi.update_settings(jsonb), realisasi.upsert_academic_year(int, text, date, date),
  realisasi.upsert_semester(int, int, realisasi.semester_term, date, date, date),
  realisasi.set_agenda_rule(int, jsonb),
  realisasi.freeze_snapshot(int, realisasi.snapshot_kind, timestamptz, uuid), realisasi.refreeze_snapshot(uuid, text),
  realisasi.run_daily_jobs(),
  realisasi.mark_notifications_read(bigint[]), realisasi.log_export(text, jsonb, int, boolean),
  realisasi.period_info(int, text), realisasi.dashboard(int, text, int), realisasi.international_awards(int, text, int),
  realisasi.kpi_drilldown(int, text, text, text, int, uuid), realisasi.kpi_participant_rows(int, text, int, uuid),
  realisasi.activity_detail(uuid), realisasi.participant_version(uuid, int), realisasi.participant_counts(uuid),
  realisasi.nav_counts(), realisasi.agreement_realization(int), realisasi.agreement_flags(int),
  realisasi.snapshot_list(int), realisasi.snapshot_detail(uuid),
  realisasi.snapshot_late_additions(uuid), realisasi.snapshot_post_freeze_changes(uuid)
  to authenticated;

-- >>> supabase/migrations/0017_pg_cron.sql
-- 0017_pg_cron: schedule run_daily_jobs at 18:00 UTC (01:00 WIB) when pg_cron is available.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('realisasi-daily-jobs', '0 18 * * *', $c$select realisasi.run_daily_jobs()$c$);
  end if;
exception when others then
  raise notice 'pg_cron unavailable: %', sqlerrm;
end $$;

-- >>> supabase/seed-supabase/01_config.sql
-- seed-supabase/01_config (simks-partnership): same settings/calendar/Jenis Kegiatan rules/SDGs as the local demo seed
-- (deployment-agnostic; enables the demo_time_travel deployment flag). Idempotent. Applied by
-- scripts/db-deploy-supabase.sh; never by scripts/db-reset.sh. (Revisi V.1: no SLA, so SIMKS holidays are not needed.)
-- 01_config: settings, calendar, Jenis Kegiatan rules, SDGs. Idempotent and deployment-agnostic: also applied to
-- Supabase by supabase/seed-supabase/01_config.sql. Team membership lives with the accounts (00_kerjasama.sql locally,
-- seed-supabase/03_accounts.sql on Supabase).

-- Demo deployment: enable demo_today time travel (M9). Production does not run seeds, so the flag stays absent (= off).
-- To disable on an existing database: update realisasi.deployment_flags set enabled = false where key = 'demo_time_travel';
insert into realisasi.deployment_flags (key, enabled) values ('demo_time_travel', true) on conflict (key) do nothing;

insert into realisasi.settings (key, value) values
  ('grace_period_months', '6'), ('reporting_deadline_days', '30'), ('revision_reminder_days', '7'),
  ('deadline_reminder_before_days', '7'), ('demo_today', 'null')
on conflict (key) do nothing;

insert into realisasi.academic_years (id, label, start_date, end_date) values
  (1, '2025/2026', '2025-08-01', '2026-07-31'),
  (2, '2026/2027', '2026-08-01', '2027-07-31')
on conflict (id) do update set label = excluded.label, start_date = excluded.start_date, end_date = excluded.end_date;

insert into realisasi.semesters (id, academic_year_id, term, start_date, end_date, cutoff_date) values
  (1, 1, 'ganjil', '2025-08-01', '2026-01-31', '2026-03-02'),
  (2, 1, 'genap',  '2026-02-01', '2026-07-31', '2026-08-30'),
  (3, 2, 'ganjil', '2026-08-01', '2027-01-31', '2027-03-02'),
  (4, 2, 'genap',  '2027-02-01', '2027-07-31', '2027-08-30')
on conflict (id) do update set academic_year_id = excluded.academic_year_id, term = excluded.term,
  start_date = excluded.start_date, end_date = excluded.end_date, cutoff_date = excluded.cutoff_date;


-- Jenis Kegiatan = SIMKS agenda (kerjasama.agendas). Default mobility categories (Revisi V.1); IO Admin edits them in
-- Pengaturan. Agendas without a row are non-mobility kegiatan that count for KPI 1.19.S1.
insert into realisasi.agenda_rules (agenda_id, mobility_category) values
  (16, 'jd_dd'), (17, 'jd_dd'), (18, 'jd_dd'), (85, 'jd_dd'),
  (2, 'student_exchange'), (20, 'student_exchange'), (28, 'student_exchange'), (33, 'student_exchange'),
  (22, 'short_summer'), (23, 'short_summer'), (29, 'short_summer'),
  (21, 'other_mobility'), (24, 'other_mobility'), (38, 'other_mobility')
on conflict (agenda_id) do nothing;

insert into realisasi.sdgs (id, name) values
  (1,'Tanpa Kemiskinan'), (2,'Tanpa Kelaparan'), (3,'Kehidupan Sehat dan Sejahtera'), (4,'Pendidikan Berkualitas'),
  (5,'Kesetaraan Gender'), (6,'Air Bersih dan Sanitasi Layak'), (7,'Energi Bersih dan Terjangkau'),
  (8,'Pekerjaan Layak dan Pertumbuhan Ekonomi'), (9,'Industri, Inovasi dan Infrastruktur'), (10,'Berkurangnya Kesenjangan'),
  (11,'Kota dan Permukiman yang Berkelanjutan'), (12,'Konsumsi dan Produksi yang Bertanggung Jawab'),
  (13,'Penanganan Perubahan Iklim'), (14,'Ekosistem Lautan'), (15,'Ekosistem Daratan'),
  (16,'Perdamaian, Keadilan dan Kelembagaan yang Tangguh'), (17,'Kemitraan untuk Mencapai Tujuan')
on conflict (id) do update set name = excluded.name;

select setval('realisasi.academic_years_id_seq', greatest((select max(id) from realisasi.academic_years), 1));
select setval('realisasi.semesters_id_seq', greatest((select max(id) from realisasi.semesters), 1));

-- >>> supabase/seed-supabase/02_registries.sql
-- seed-supabase/02_registries (simks-partnership): mock BAAK students / HR employees (mockup only). Idempotent.
-- 02_registries: mock BAAK (60 students) and HR (25 employees). Generated deterministically (seed 20261001).
-- NRP: {faculty A-H}{2-digit prodi}{2-digit intake}{4-digit seq}; inbound: X{term}{year}{seq}; employee: PG{6 digits}.
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values
  ('A11235253', 'Benedict Kusuma', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2023, 'graduated'),
  ('A11252034', 'Reza Tanoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2025, 'graduated'),
  ('A12223059', 'Hans Tanjung', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2022, 'active'),
  ('A12231277', 'Yosua Tanoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2023, 'inactive'),
  ('B11200005', 'Hendra Gunawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2020, 'graduated'),
  ('B11227366', 'Cindy Liem', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11234310', 'Ivan Hidayat', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11235580', 'Michael Liem', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11235901', 'Cindy Kusuma', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11237182', 'William Liem', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11238623', 'Timotius Wijaya', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11240422', 'Oscar Salim', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11244167', 'Dewi Setiawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11252003', 'Gabriel Tjahjono', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11256252', 'Lidya Sutanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11257273', 'Budi Handoko', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B12222426', 'Grace Sugianto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2022, 'active'),
  ('B12223137', 'Michael Setiawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2022, 'active'),
  ('B12229323', 'Yohana Setiawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2022, 'active'),
  ('B12249536', 'Oscar Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12251882', 'Benedict Lesmana', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12252182', 'Ivan Prasetyo', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12254341', 'Melisa Tjahjono', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12257991', 'Leonardo Wibowo', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('C21233005', 'Ivan Handoko', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21233140', 'Yosua Tjahjono', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21233729', 'Melisa Wijaya', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21247286', 'Daniel Hidayat', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21257355', 'Irene Halim', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('D31238836', 'Jonathan Handoko', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31239872', 'Irene Salim', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31240187', 'Daniel Kurniawan', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31242651', 'Gabriel Hidayat', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31243593', 'Lidya Setiawan', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31245931', 'Reza Sugianto', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31246584', 'Rafael Wijaya', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31252983', 'Lidya Tjahjono', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D32210044', 'Melisa Hartono', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 'regular', null, null, 2021, 'inactive'),
  ('D32233592', 'Budi Purnomo', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32237864', 'Jonathan Salim', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32250736', 'Theresia Setiawan', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('E41251767', 'Kezia Kusuma', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2025, 'active'),
  ('F51245128', 'Hans Susanto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('G61248918', 'Theresia Tanjung', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2024, 'active'),
  ('H71235980', 'Theresia Pranoto', 'H', 'Program Pascasarjana', 'Magister Manajemen', 'regular', null, null, 2023, 'active'),
  ('X01260012', 'Maria Santos', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'De La Salle University', 'PH', 2026, 'active'),
  ('X01250003', 'Haruto Sato', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Institute of Technology', 'JP', 2025, 'active'),
  ('X01250017', 'Yui Takahashi', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Institute of Technology', 'JP', 2025, 'active'),
  ('X01250024', 'Ren Watanabe', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Institute of Technology', 'JP', 2025, 'active'),
  ('X02260008', 'Min-jun Kim', 'C', 'Fakultas Seni dan Desain', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hanyang University', 'KR', 2026, 'active'),
  ('X02260015', 'Seo-yeon Park', 'C', 'Fakultas Seni dan Desain', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hanyang University', 'KR', 2026, 'active'),
  ('X02250031', 'Chia-hao Lin', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University of Science and Technology', 'TW', 2025, 'active'),
  ('X01260027', 'Yu-ting Chen', 'D', 'Fakultas Bisnis dan Ekonomi', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Tunghai University', 'TW', 2026, 'active'),
  ('X02250042', 'Lukas Schneider', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hochschule Bremen', 'DE', 2025, 'active'),
  ('X01260035', 'Lea Fischer', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universität Stuttgart', 'DE', 2026, 'active'),
  ('X02250056', 'Daan de Vries', 'D', 'Fakultas Bisnis dan Ekonomi', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Fontys University of Applied Sciences', 'NL', 2025, 'active'),
  ('X02250063', 'Sanne Jansen', 'D', 'Fakultas Bisnis dan Ekonomi', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Fontys University of Applied Sciences', 'NL', 2025, 'active'),
  ('X01260044', 'Olivia Brown', 'C', 'Fakultas Seni dan Desain', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'The University of Queensland', 'AU', 2026, 'active'),
  ('X01260051', 'Nur Aisyah binti Rahman', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universiti Teknologi Malaysia', 'MY', 2026, 'active'),
  ('X01260068', 'Kittipong Srisuk', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'King Mongkuts University of Technology Thonburi', 'TH', 2026, 'active')
on conflict (nrp) do update set full_name = excluded.full_name, faculty_code = excluded.faculty_code,
  faculty_name = excluded.faculty_name, prodi_name = excluded.prodi_name, category = excluded.category,
  home_institution = excluded.home_institution, home_country_code = excluded.home_country_code,
  intake_year = excluded.intake_year, status = excluded.status;

insert into mock_hr.employees (employee_id, full_name, unit_name, position, status) values
  ('PG124885', 'Angelina Wibowo, S.E.', 'Program Studi Desain Komunikasi Visual', 'Lektor Kepala', 'inactive'),
  ('PG190875', 'Ir. Reza Prasetyo, M.M.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG204517', 'Ir. Bambang Sutrisno, M.T.', 'Program Studi Teknik Elektro', 'Lektor Kepala', 'active'),
  ('PG214411', 'Eunike Susanto, M.M.', 'Program Studi Manajemen', 'Staf Administrasi', 'active'),
  ('PG217839', 'Wilson Tanjung, M.M.', 'Fakultas Bisnis & Ekonomi', 'Staf Administrasi', 'active'),
  ('PG295222', 'Ir. Felicia Wibowo, M.M.', 'Program Studi Manajemen', 'Dosen', 'active'),
  ('PG378607', 'Dr. Patricia Kurniawan, S.E.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG413450', 'Dr. Gabriel Saputra, M.M.', 'Program Studi Teknik Elektro', 'Lektor Kepala', 'active'),
  ('PG427328', 'Jonathan Prasetyo, S.E.', 'International Office', 'Staf Administrasi', 'active'),
  ('PG452412', 'Andreas Prasetyo, M.Sc.', 'Program Studi Desain Komunikasi Visual', 'Kepala Program Studi', 'active'),
  ('PG488192', 'Ir. Yosua Gunawan, M.M.', 'Program Studi Informatika', 'Tenaga Kependidikan', 'active'),
  ('PG561867', 'Edwin Purnomo, M.Ds.', 'Program Studi Manajemen', 'Staf Administrasi', 'active'),
  ('PG564518', 'Ir. Kevin Santoso, M.Ds.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG637448', 'Leonardo Prasetyo, M.Sc.', 'International Office', 'Staf Administrasi', 'active'),
  ('PG657970', 'Yohana Wibowo, M.Sc.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG703063', 'Kevin Wibowo, S.E.', 'Program Studi Teknik Elektro', 'Dosen', 'active'),
  ('PG707752', 'Patricia Saputra, M.Ds.', 'Fakultas Teknologi Industri', 'Tenaga Kependidikan', 'active'),
  ('PG710955', 'Yosua Sugianto, M.T.', 'Program Studi Informatika', 'Lektor Kepala', 'active'),
  ('PG712740', 'Jonathan Gunawan, M.M.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG760736', 'Ir. Hendra Sugianto, M.Ds.', 'Program Studi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG761401', 'Eunike Gunawan, M.T.', 'Fakultas Seni & Desain', 'Kepala Program Studi', 'active'),
  ('PG780858', 'Natalia Susanto, S.E.', 'Program Studi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG803275', 'Yohana Sugianto, S.E.', 'International Office', 'Tenaga Kependidikan', 'inactive'),
  ('PG818524', 'Olivia Hidayat, M.Sc.', 'Fakultas Bisnis & Ekonomi', 'Dosen', 'active'),
  ('PG974721', 'Michael Tanoto, M.T.', 'Fakultas Bisnis & Ekonomi', 'Staf Administrasi', 'active')
on conflict (employee_id) do update set full_name = excluded.full_name, unit_name = excluded.unit_name,
  position = excluded.position, status = excluded.status;

-- >>> supabase/seed-supabase/03_accounts.sql
-- seed-supabase/03_accounts (simks-partnership): which REAL SIMKS accounts (public.akun) use SIM Realisasi, and their
-- verification teams. Written only into realisasi.*; SIMKS roles are untouched. Idempotent: re-running resets these
-- accounts to the roles below (other account_roles rows are left alone). Revisi V.1: one verification team (Mobility).
--   akun  1 kepala-kui@petra.ac.id          io_admin   (mobility)
--   akun 11 staff-partnership@petra.ac.id   io_staff   (mobility)
--   akun 10 head-partnership@petra.ac.id    io_staff   (mobility)
--   akun  3 dekan-sbm@petra.ac.id           submitter  unit 4 (School of Business and Management)
--   akun  4 kaprodi-manajemen@petra.ac.id   submitter  unit 5 (Program Studi Manajemen)
--   akun  9 viewer@petra.ac.id              viewer
--   akun  6 rektor@petra.ac.id              viewer
do $$
declare missing int[];
begin
  select array_agg(x order by x) into missing from unnest(array[1, 3, 4, 6, 9, 10, 11]) x
   where not exists (select 1 from public.akun a where a.id = x);
  if missing is not null then
    raise exception 'SIMKS akun % not found; adjust supabase/seed-supabase/03_accounts.sql', missing;
  end if;
end $$;

insert into realisasi.account_roles (akun_id, app_role, unit_id) values
  (1, 'io_admin', null), (11, 'io_staff', null), (10, 'io_staff', null),
  (3, 'submitter', 4), (4, 'submitter', 5),
  (9, 'viewer', null), (6, 'viewer', null)
on conflict (akun_id) do update set app_role = excluded.app_role, unit_id = excluded.unit_id, updated_at = now();

insert into realisasi.team_members (account_id, team)
select p.id, t.team::realisasi.team
  from (values (1, 'mobility'), (11, 'mobility'), (10, 'mobility')) t(akun_id, team)
  join kerjasama.profiles p on p.akun_id = t.akun_id
on conflict do nothing;

-- >>> supabase/seed-supabase/04_activities.sql
-- seed-supabase/04_activities (simks-partnership): a dozen demo activities linked to REAL SIMKS documents, written only
-- into realisasi.* (partner snapshots come from kerjasama.partners via the activity_documents trigger). Dates lie inside
-- each document's validity and inside AY 2025/2026 – 2026/2027. Idempotent: an activity that exists is skipped.
-- Actors are resolved from realisasi.account_roles (03_accounts.sql) through kerjasama.profiles:
--   submitters akun 3 (unit 4, SBM) and akun 4 (unit 5, Program Studi Manajemen); mobility team akun 10.
-- Revisi V.1: Jenis = SIMKS agenda, Inbound/Outbound per kegiatan, one kerja sama, Mobility the only verification
-- (non-mobility kegiatan verified on submit), one open student conflict between SBM and Program Studi Manajemen (S-13).
-- Ids: activities b5000000-0000-4000-8000-0000000000NN, event groups e5000000-…NN, codes RL-2026-00NN.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;
create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- preconditions: accounts seeded, every referenced SIMKS document present and selectable
do $$
declare d int;
begin
  if pg_temp.akun(3) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 3, 4, 10)';
  end if;
  foreach d in array array[11, 15, 17, 19, 25, 27, 28, 29, 33, 34, 36, 42, 44] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/04_activities.sql', d;
    end if;
  end loop;
end $$;

create or replace function pg_temp.act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text := 'RL-2026-' || lpad(p_n::text, 4, '0');
        v_creator uuid := pg_temp.akun(case p_unit when 4 then 3 when 5 then 4 end);
        v_mobt uuid := pg_temp.akun(10); v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'no submitter account for unit %', p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'activity %: SIMKS agenda % missing', p_n, p_agenda; end if;
  -- R-04 against the live SIMKS data: the agreement is valid for the activity dates
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'activity %: SIMKS document % not valid for % – %', p_n, p_doc, p_start, p_end;
  end if;

  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then 3 end,
          'Kegiatan "' || p_name || '" dalam rangka implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', v_mobt, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', v_mobt, p_msince, p_mnote); end if;
end $$;

create or replace function pg_temp.pset(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz default null) returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, v_by, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(10) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- ---- AY 2025/2026 (verified) -------------------------------------------------------------------------------------
-- agendas: 2 Student Exchange, 23 Short Program (mobility); 4 Joint Research, 15 Kuliah Tamu, 35 Joint Projects,
-- 40 Pengabdian (non-mobility)
select pg_temp.act(1, 'Student Exchange Semester Ganjil di Kyoto Sangyo University', 4, 2, 'outbound', '2025-09-01', '2025-12-19', 'offline',
  'Kyoto Sangyo University', 'JP', 11, '{4,17}', pg_temp.wib('2025-12-22'), 'approved', pg_temp.wib('2026-01-08', '14:00'));
select pg_temp.pset(1, 'approved', '{D31238836,D31239872,D32233592}', '{}', '{}', pg_temp.wib('2025-12-22'), pg_temp.wib('2026-01-08', '14:00'));

select pg_temp.act(2, 'Pengabdian Masyarakat UMKM Digital bersama UGM', 5, 40, 'outbound', '2025-11-10', '2025-11-14', 'offline',
  'Desa Wisata Nglanggeran', 'ID', 28, '{1,8}', pg_temp.wib('2025-11-20'), null, null);

select pg_temp.act(3, 'Joint Seminar Bisnis Berkelanjutan ASEAN bersama Chulalongkorn', 4, 35, 'inbound', '2026-01-20', '2026-01-21', 'hybrid',
  'Auditorium PCU', 'ID', 29, '{8,17}', pg_temp.wib('2026-01-26'), null, null,
  p_ext => '[{"full_name":"Asst. Prof. Kanokwan Srisuk","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.act(4, 'Kuliah Tamu Manajemen Inovasi dari National Taiwan University', 4, 15, 'inbound', '2026-03-09', '2026-03-13', 'offline',
  'Gedung T PCU', 'ID', 15, '{4,9}', pg_temp.wib('2026-03-18'), null, null,
  p_ext => '[{"full_name":"Prof. Chen Yu-Ting","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.act(5, 'Riset Bersama Perilaku Konsumen Digital dengan University of Amsterdam', 5, 4, 'outbound', '2026-04-06', '2026-06-30', 'online',
  'Zoom Meeting', null, 17, '{8,9}', pg_temp.wib('2026-07-06'), null, null);

select pg_temp.act(6, 'Summer Program Business in Asia di Chulalongkorn University', 4, 23, 'outbound', '2026-07-06', '2026-07-24', 'offline',
  'Chulalongkorn University', 'TH', 25, '{4,17}', pg_temp.wib('2026-07-29'), 'approved', pg_temp.wib('2026-08-05', '14:00'));
select pg_temp.pset(6, 'approved', '{D31242651,D31245931,D32237864,D31246584}', '{}', '{PG217839}', pg_temp.wib('2026-07-29'),
  pg_temp.wib('2026-08-05', '14:00'));

-- ---- AY 2026/2027 Ganjil --------------------------------------------------------------------------------------------
select pg_temp.act(7, 'Inbound Exchange Manajemen National University of Singapore 2026', 5, 2, 'inbound', '2026-08-10', '2026-09-11', 'offline',
  'Kampus PCU Siwalankerto', 'ID', 19, '{4}', pg_temp.wib('2026-09-14'), 'approved', pg_temp.wib('2026-09-18', '14:00'));
select pg_temp.pset(7, 'approved', '{}', '{X01260012,X01260044}', '{}', pg_temp.wib('2026-09-14'), pg_temp.wib('2026-09-18', '14:00'));

select pg_temp.act(8, 'Riset Bersama Ekonomi Sirkular dengan LMU Munich', 5, 4, 'inbound', '2026-09-07', '2026-09-11', 'hybrid',
  'Lab Manajemen PCU', 'ID', 42, '{9,12}', pg_temp.wib('2026-09-15'), null, null);

-- renewal chain 29 -> 34 (Chulalongkorn MoA): non-mobility seminar on the renewal, verified on submit
select pg_temp.act(9, 'Joint Seminar Rantai Pasok Asia Tenggara (lanjutan)', 4, 35, 'inbound', '2026-09-23', '2026-09-24', 'offline',
  'Gedung T PCU', 'ID', 34, '{9}', pg_temp.daysago(5), null, null);

-- renewal chain 28 -> 33 (UGM MoU)
select pg_temp.act(10, 'Seminar Nasional Kewirausahaan bersama UGM', 5, 35, 'inbound', '2026-09-24', '2026-09-25', 'offline',
  'Auditorium PCU', 'ID', 33, '{4,8}', pg_temp.daysago(2), null, null);

-- waiting for Verifikasi Mobilitas
select pg_temp.act(11, 'Student Exchange Singkat di National University of Singapore', 4, 2, 'outbound', '2026-09-01', '2026-09-19', 'offline',
  'National University of Singapore', 'SG', 36, '{4}', pg_temp.daysago(6), 'pending', pg_temp.daysago(6));
select pg_temp.pset(11, 'pending', '{D31252983,D32250736,D31243593}', '{}', '{}', pg_temp.daysago(6));

-- draft (only IA uploaded)
select pg_temp.act(12, 'Kuliah Tamu Pemasaran Global dari Ateneo de Manila University', 4, 15, 'inbound', '2026-09-28', '2026-09-29', 'online',
  'Zoom Meeting', null, 44, '{4}', null, null, null, p_files => '{ia}');

-- rule 2.1 demo: Program Studi Manajemen claims two of SBM's summer-program students (S-06) -> open conflict in the queue
select pg_temp.act(13, 'Summer Program Business in Asia (Program Studi Manajemen)', 5, 23, 'outbound', '2026-07-06', '2026-07-24', 'offline',
  'Chulalongkorn University', 'TH', 25, '{4}', pg_temp.daysago(4), 'pending', pg_temp.daysago(4));
select pg_temp.pset(13, 'pending', '{D31242651,D31245931}', '{}', '{}', pg_temp.daysago(4));
select realisasi._scan_conflicts(pg_temp.aid(13)) where not exists (select 1 from realisasi.participant_conflicts where pg_temp.aid(13) in (activity_a, activity_b));

select setval('realisasi.activity_code_seq', greatest(100, (select last_value from realisasi.activity_code_seq)));

-- >>> supabase/seed-supabase/05_registries_bulk.sql
-- seed-supabase/05_registries_bulk (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- Mock BAAK/HR registries for the bulk kegiatan: 274 PETRA students across 23 Program Studi, 82 inbound exchange students, 56 lecturers.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

-- PETRA students of every Program Studi (prodi_name = the SIMKS unit name without "Prodi"/"Program Studi")
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values
  ('D31227308', 'Marcella Liem', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31256420', 'Olivia Purnomo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31248545', 'Rachel Salim', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31248243', 'Gloria Hermawan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31248402', 'Irene Hartono', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31228515', 'Felicia Gunawan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31236401', 'Irene Wijaya', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31258008', 'Dionisius Lesmana', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31237627', 'Rafael Tjahjono', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31237541', 'Hizkia Liem', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31256312', 'Gloria Lesmana', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31228283', 'Priscilla Sutanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31237873', 'Jonathan Purnomo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31258883', 'Filbert Sugianto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31236101', 'Filbert Tjahjono', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31237888', 'Grace Santoso', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31248399', 'Rachel Susanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31227742', 'Marcella Chandra', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31248011', 'Devina Effendi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31247059', 'Evan Sugianto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31248101', 'Natasha Chandra', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31228357', 'Olivia Hermawan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31236200', 'Filbert Liem', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31258938', 'Yosef Salim', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31246583', 'Kezia Purnomo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31236499', 'Aurelia Budiman', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31248761', 'Kezia Budiman', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31247028', 'Rachel Hidayat', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D32257260', 'Rachel Chandra', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32258055', 'Eunike Susanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32247773', 'Michelle Sutanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32236037', 'Christian Tanoto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32258446', 'Jessica Chandra', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32248005', 'Bryan Effendi', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32237065', 'Jessica Liem', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32247778', 'Rachel Tanjung', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32227188', 'Wilson Wibowo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32227795', 'Eunike Budiman', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32247060', 'Irene Effendi', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32237743', 'Gloria Susanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32228656', 'Stefani Purnomo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32247516', 'Gabriel Setiawan', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32257684', 'Jonathan Wibowo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32226377', 'Andreas Wibowo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32248238', 'Felicia Wirawan', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32237015', 'Hana Wirawan', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32228238', 'Stefani Tanjung', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32257463', 'Jonathan Wijaya', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('H71258722', 'Timothy Sugianto', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('H71258825', 'Gloria Tanoto', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('H71247937', 'Timothy Tanoto', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71256345', 'Evan Tanjung', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('H71246554', 'Timothy Sutanto', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71257599', 'Jonathan Liem', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('H72247540', 'Andreas Gunawan', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2024, 'active'),
  ('H72256300', 'Daniel Lim', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2025, 'active'),
  ('H72258647', 'Agnes Effendi', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2025, 'active'),
  ('H72246104', 'Marcella Susanto', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2024, 'active'),
  ('H72258796', 'Vincent Wibowo', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2025, 'active'),
  ('H72256497', 'Lukas Wibowo', 'H', 'School of Business and Management', 'Doktor Ilmu Manajemen', 'regular', null, null, 2025, 'active'),
  ('A12248533', 'Kevin Tanoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12248128', 'Nathaniel Salim', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12247377', 'Jessica Wirawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12238779', 'Filbert Santoso', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2023, 'active'),
  ('A12247634', 'Christian Setiawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12256710', 'Christian Kusuma', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A12246197', 'Irene Siswanto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12256772', 'Dionisius Purnomo', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A12226528', 'Benaya Liem', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2022, 'active'),
  ('A12238117', 'Ivana Kurniawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2023, 'active'),
  ('A12256761', 'Clarissa Pranoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A12248183', 'Evan Siswanto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A12227569', 'Vincent Kurniawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2022, 'active'),
  ('A12236715', 'Rafael Wibowo', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 'regular', null, null, 2023, 'active'),
  ('A13257702', 'Theresia Wibowo', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A13247334', 'Natasha Susanto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A13256491', 'Stefani Lim', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A13246877', 'Olivia Wijaya', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A13247860', 'Benaya Lesmana', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2024, 'active'),
  ('A13258232', 'Cornelius Kurniawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Arsitektur', 'regular', null, null, 2025, 'active'),
  ('A11227441', 'Kevin Tjahjono', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2022, 'active'),
  ('A11248814', 'Samuel Chandra', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A11246886', 'Filbert Pranoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A11248326', 'Gloria Setiawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A11247207', 'Samuel Pranoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A11258276', 'Ivana Gunawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2025, 'active'),
  ('A11236394', 'Grace Kurniawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2023, 'active'),
  ('A11228803', 'Daniel Hermawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2022, 'active'),
  ('A11238958', 'Laurensia Kusuma', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2023, 'active'),
  ('A11256435', 'Marcella Lesmana', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2025, 'active'),
  ('A11238408', 'Elisabeth Sutanto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2023, 'active'),
  ('A11236661', 'Rafael Pranoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2023, 'active'),
  ('A11226056', 'Kristo Pranoto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2022, 'active'),
  ('A11246063', 'Daniel Gunawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A14246094', 'Vincent Gunawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A14248809', 'Rachel Sugianto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A14257290', 'Kristo Wibowo', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2025, 'active'),
  ('A14247655', 'Wilson Wirawan', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A14248433', 'Jessica Salim', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('A14248811', 'Bryan Siswanto', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Magister Teknik Sipil', 'regular', null, null, 2024, 'active'),
  ('E42248791', 'Rafael Hidayat', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E42237459', 'Daniel Saputra', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42257788', 'Bella Sutanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2025, 'active'),
  ('E42257353', 'Theresia Saputra', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2025, 'active'),
  ('E42227216', 'Kristo Salim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2022, 'active'),
  ('E42238398', 'Bella Handoko', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42236808', 'Rachel Halim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42256461', 'Kevin Wirawan', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2025, 'active'),
  ('E42226484', 'Natasha Tjahjono', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2022, 'active'),
  ('E42248653', 'Benaya Sutanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E42227739', 'Agnes Salim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2022, 'active'),
  ('E42247544', 'Patricia Hermawan', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E43248713', 'Priscilla Wijaya', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2024, 'active'),
  ('E43258937', 'Priscilla Tanjung', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2025, 'active'),
  ('E43247625', 'Rafael Chandra', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2024, 'active'),
  ('E43236934', 'Bella Wijaya', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2023, 'active'),
  ('E43238216', 'Kezia Salim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2023, 'active'),
  ('E43237289', 'Ivana Kusuma', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2023, 'active'),
  ('E43246366', 'Laurensia Handoko', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2024, 'active'),
  ('E43228663', 'Marcella Lim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2022, 'active'),
  ('E43237395', 'Aurelia Liem', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2023, 'active'),
  ('E43257300', 'Daniel Tanjung', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 'regular', null, null, 2025, 'active'),
  ('C22228571', 'Patricia Susanto', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22226908', 'Dionisius Liem', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22237634', 'Olivia Handoko', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22237407', 'Michelle Tjahjono', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22237881', 'Aurelia Wibowo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22247941', 'Dionisius Sugianto', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22236769', 'Kevin Kusuma', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22246629', 'Lukas Purnomo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22227451', 'Natasha Budiman', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22246153', 'Aurelia Kurniawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22227224', 'Bryan Handoko', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22257085', 'Ivana Budiman', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2025, 'active'),
  ('E41256412', 'Nathaniel Siswanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2025, 'active'),
  ('E41258385', 'Vincent Sugianto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2025, 'active'),
  ('E41227610', 'Clarissa Handoko', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2022, 'active'),
  ('E41248638', 'Marcella Gunawan', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2024, 'active'),
  ('E41226581', 'Gloria Hidayat', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2022, 'active'),
  ('E41238242', 'Rafael Sutanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2023, 'active'),
  ('E41228427', 'Cornelius Chandra', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2022, 'active'),
  ('E41236664', 'Theresia Sutanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2023, 'active'),
  ('E41247169', 'Agnes Tanoto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2024, 'active'),
  ('E41246772', 'Hizkia Kusuma', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2024, 'active'),
  ('E41228481', 'Benaya Susanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2022, 'active'),
  ('E41247456', 'Kristo Purnomo', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 'regular', null, null, 2024, 'active'),
  ('C21246699', 'Gloria Liem', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21226735', 'Wilson Handoko', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21236671', 'Bella Purnomo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21228109', 'Cornelius Purnomo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21258635', 'Kristo Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21236260', 'Bryan Sutanto', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21238179', 'Jonathan Wirawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21247016', 'Wilson Susanto', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21228976', 'Elisabeth Hidayat', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21238527', 'Vincent Kusuma', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21227424', 'Kezia Effendi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21246495', 'Rachel Liem', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21237469', 'Dionisius Lim', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21248397', 'Agnes Santoso', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21226359', 'Lukas Hermawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21237086', 'Jesslyn Tanjung', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('E44246689', 'Wilson Salim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2024, 'active'),
  ('E44257321', 'Gloria Tanjung', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2025, 'active'),
  ('E44257650', 'Wilson Kurniawan', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2025, 'active'),
  ('E44247896', 'Olivia Siswanto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2024, 'active'),
  ('E44257434', 'Evan Lim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2025, 'active'),
  ('E44256871', 'Hizkia Sugianto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Magister Sastra', 'regular', null, null, 2025, 'active'),
  ('B12256522', 'Grace Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12236482', 'Wilson Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12247079', 'Jonathan Handoko', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12257098', 'Olivia Lesmana', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12238299', 'Kristo Gunawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12237202', 'Samuel Wibowo', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12257643', 'Devina Wijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12248934', 'Yohanes Tanjung', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12247379', 'Gabriel Tanjung', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12248777', 'Aurelia Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12258238', 'Natasha Setiawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12247442', 'Daniel Effendi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12248967', 'Laurensia Wijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12238289', 'Eunike Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B13237368', 'Timothy Kusuma', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13247698', 'Kristo Chandra', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13247978', 'Yohanes Wijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13226900', 'Aurelia Gunawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2022, 'active'),
  ('B13257100', 'Wilson Wijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('B13237872', 'Marcella Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13248581', 'Bryan Santoso', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13248836', 'Michelle Handoko', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13226391', 'Jonathan Lesmana', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2022, 'active'),
  ('B13237898', 'Nathaniel Wirawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13256699', 'Filbert Sutanto', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('B13228324', 'Evan Budiman', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2022, 'active'),
  ('B13248789', 'Timothy Handoko', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13236442', 'Bella Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13246182', 'Olivia Effendi', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13248694', 'Cornelius Lesmana', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B11237423', 'Kezia Pranoto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11247339', 'Rafael Halim', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11258007', 'Ivana Wijaya', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11247499', 'Rafael Lim', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11246814', 'Bryan Pranoto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11248998', 'Devina Sutanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11238382', 'Elisabeth Saputra', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11258643', 'Cornelius Liem', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11258180', 'Kristo Siswanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11237976', 'Yosef Santoso', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11248139', 'Valencia Lesmana', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11247302', 'Bryan Kurniawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11228302', 'Laurensia Hermawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11238162', 'Natasha Siswanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11248582', 'Gabriel Effendi', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11246879', 'Bella Wibowo', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11236858', 'Grace Liem', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11246518', 'Marcella Setiawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11238934', 'Lukas Tanoto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11248779', 'Wilson Tjahjono', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11257605', 'Priscilla Wirawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11258208', 'Michelle Tanoto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B14248258', 'Filbert Tanoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2024, 'active'),
  ('B14256589', 'Ivana Chandra', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14258346', 'Daniel Chandra', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14256141', 'Stefani Chandra', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14236733', 'Ivana Pranoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14248838', 'Jessica Kurniawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2024, 'active'),
  ('B14238838', 'Laurensia Tanjung', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14237695', 'Benaya Wirawan', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14248236', 'Olivia Liem', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2024, 'active'),
  ('B14238223', 'Felicia Wibowo', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14257666', 'Wilson Tanoto', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14258081', 'Christian Susanto', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B15246238', 'Gabriel Tjahjono', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B15257346', 'Jesslyn Wijaya', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('B15248061', 'Michelle Siswanto', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B15247731', 'Cornelius Salim', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B15246699', 'Patricia Hartono', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B15256871', 'Priscilla Siswanto', 'B', 'Fakultas Teknologi Industri', 'Magister Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('F52248953', 'Grace Wibowo', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2024, 'active'),
  ('F52238887', 'Nathaniel Sutanto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2023, 'active'),
  ('F52257804', 'Rachel Wirawan', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2025, 'active'),
  ('F52246375', 'Nathaniel Saputra', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2024, 'active'),
  ('F52236474', 'Jesslyn Santoso', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2023, 'active'),
  ('F52238927', 'Dionisius Wirawan', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2023, 'active'),
  ('F52256647', 'Hana Kurniawan', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2025, 'active'),
  ('F52238625', 'Grace Setiawan', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Pendidikan Anak Usia Dini', 'regular', null, null, 2023, 'active'),
  ('F51246124', 'Rachel Tanoto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('F51258597', 'Stefani Sutanto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2025, 'active'),
  ('F51257495', 'Kezia Liem', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2025, 'active'),
  ('F51247118', 'Agnes Susanto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('F51236440', 'Olivia Tjahjono', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2023, 'active'),
  ('F51247545', 'Valencia Kusuma', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('F51246197', 'Eunike Tanjung', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('F51247336', 'Jesslyn Pranoto', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2024, 'active'),
  ('F51256322', 'Jessica Wibowo', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2025, 'active'),
  ('F51238236', 'Natasha Lim', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 'regular', null, null, 2023, 'active'),
  ('G61246402', 'Christian Santoso', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2024, 'active'),
  ('G61246171', 'Elisabeth Liem', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2024, 'active'),
  ('G61248311', 'Gabriel Hidayat', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2024, 'active'),
  ('G61258355', 'Kezia Handoko', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2025, 'active'),
  ('G61226627', 'Bella Gunawan', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2022, 'active'),
  ('G61246376', 'Kevin Handoko', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2024, 'active'),
  ('G61236074', 'Christian Saputra', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2023, 'active'),
  ('G61228465', 'Natasha Gunawan', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2022, 'active'),
  ('G61257371', 'Vincent Susanto', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2025, 'active'),
  ('G61237319', 'Filbert Purnomo', 'G', 'Fakultas Kedokteran', 'Kedokteran', 'regular', null, null, 2023, 'active'),
  ('G62248828', 'Patricia Hidayat', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2024, 'active'),
  ('G62238105', 'Patricia Wirawan', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2023, 'active'),
  ('G62237796', 'Michelle Hermawan', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2023, 'active'),
  ('G62228409', 'Kezia Sugianto', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2022, 'active'),
  ('G62247977', 'Natasha Wijaya', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2024, 'active'),
  ('G62246895', 'Clarissa Saputra', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2024, 'active'),
  ('G62228168', 'Ivana Sutanto', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2022, 'active'),
  ('G62238135', 'Bella Tjahjono', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 'regular', null, null, 2023, 'active')
on conflict (nrp) do nothing;

-- inbound exchange students from the partner universities
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values
  ('X03250301', 'Haruka Tanaka', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260302', 'Haruka Nakamura', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250303', 'Sota Yamamoto', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260304', 'Sota Nakamura', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250305', 'Yuna Kobayashi', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260306', 'Yuna Yamamoto', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250307', 'Ren Ito', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260308', 'Ren Nakamura', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250309', 'Aoi Nakamura', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260310', 'Aoi Tanaka', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250311', 'Kaito Suzuki', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2025, 'active'),
  ('X04260312', 'Kaito Nakamura', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kyoto Sangyo University', 'JP', 2026, 'active'),
  ('X03250313', 'Wei-Lun Chang', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X04260314', 'Wei-Lun Liu', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X03250315', 'Yi-Chen Huang', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X04260316', 'Yi-Chen Huang', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X03250317', 'Po-Han Liu', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X04260318', 'Po-Han Lee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X03250319', 'Hsin-Yi Wu', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X04260320', 'Hsin-Yi Chang', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X03250321', 'Chun-Kai Lee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X04260322', 'Chun-Kai Lee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X03250323', 'Sanne de Jong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2025, 'active'),
  ('X04260324', 'Sanne Bakker', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2026, 'active'),
  ('X03250325', 'Lars Bakker', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2025, 'active'),
  ('X04260326', 'Lars Mulder', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2026, 'active'),
  ('X03250327', 'Femke Visser', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2025, 'active'),
  ('X04260328', 'Femke Mulder', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2026, 'active'),
  ('X03250329', 'Thijs Mulder', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2025, 'active'),
  ('X04260330', 'Thijs Jong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2026, 'active'),
  ('X03250331', 'Rachel Tan', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X04260332', 'Rachel Tan', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X03250333', 'Marcus Lim', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X04260334', 'Marcus Ong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X03250335', 'Priya Nair', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X04260336', 'Priya Ong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X03250337', 'Darren Ong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X04260338', 'Darren Tan', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X03250339', 'Shu Hui Goh', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X04260340', 'Shu Lim', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X03250341', 'Natcha Srisuk', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X04260342', 'Natcha Chaiyasit', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X03250343', 'Pakorn Chaiyasit', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X04260344', 'Pakorn Srisuk', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X03250345', 'Siriporn Wong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X04260346', 'Siriporn Wong', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X03250347', 'Thanawat Boonmee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X04260348', 'Thanawat Chaiyasit', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X03250349', 'Kanya Rattanakorn', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X04260350', 'Kanya Rattanakorn', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X03250351', 'Ji-woo Kim', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  ('X04260352', 'Ji-woo Park', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X03250353', 'Seo-jun Lee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  ('X04260354', 'Seo-jun Park', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X03250355', 'Ha-eun Park', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  ('X04260356', 'Ha-eun Kim', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X03250357', 'Min-seo Choi', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  ('X04260358', 'Min-seo Park', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X03250359', 'Do-yoon Jung', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  ('X04260360', 'Do-yoon Lee', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X03250361', 'Lena Hoffmann', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2025, 'active'),
  ('X04260362', 'Lena Hoffmann', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2026, 'active'),
  ('X03250363', 'Jonas Weber', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2025, 'active'),
  ('X04260364', 'Jonas Weber', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2026, 'active'),
  ('X03250365', 'Mia Schulz', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2025, 'active'),
  ('X04260366', 'Mia Hoffmann', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2026, 'active'),
  ('X03250367', 'Felix Wagner', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2025, 'active'),
  ('X04260368', 'Felix Wagner', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ludwig Maximilian University of Munich', 'DE', 2026, 'active'),
  ('X03250369', 'Andrea Santos', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2025, 'active'),
  ('X04260370', 'Andrea Santos', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2026, 'active'),
  ('X03250371', 'Miguel Reyes', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2025, 'active'),
  ('X04260372', 'Miguel Cruz', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2026, 'active'),
  ('X03250373', 'Bea Cruz', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2025, 'active'),
  ('X04260374', 'Bea Garcia', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2026, 'active'),
  ('X03250375', 'Paolo Garcia', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2025, 'active'),
  ('X04260376', 'Paolo Santos', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Ateneo de Manila University', 'PH', 2026, 'active'),
  ('X03250377', 'Olivia Brown', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2025, 'active'),
  ('X04260378', 'Olivia Brown', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2026, 'active'),
  ('X03250379', 'Jack Wilson', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2025, 'active'),
  ('X04260380', 'Jack Taylor', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2026, 'active'),
  ('X03250381', 'Chloe Taylor', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2025, 'active'),
  ('X04260382', 'Chloe Taylor', 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Sydney', 'AU', 2026, 'active')
on conflict (nrp) do nothing;

-- lecturers and heads of every Program Studi
insert into mock_hr.employees (employee_id, full_name, unit_name, position, status) values
  ('PG626211', 'Dr. Theresia Santoso, M.M.', 'Program Studi Manajemen', 'Ketua Program Studi', 'active'),
  ('PG670883', 'Dr. Stefani Setiawan, M.T.', 'Program Studi Manajemen', 'Dosen', 'active'),
  ('PG661938', 'Dr. Rafael Santoso, Ph.D.', 'Program Studi Manajemen', 'Lektor Kepala', 'active'),
  ('PG643269', 'Rachel Kusuma, M.Pd.', 'Program Studi Manajemen', 'Lektor Kepala', 'active'),
  ('PG641614', 'Lukas Lim, M.T.', 'Program Studi Akuntansi', 'Ketua Program Studi', 'active'),
  ('PG641995', 'Devina Wibowo, M.T.', 'Program Studi Akuntansi', 'Dosen', 'active'),
  ('PG508242', 'Dr. Evan Hidayat, M.Pd.', 'Program Studi Akuntansi', 'Dosen', 'active'),
  ('PG615640', 'Kevin Hartono, M.M.', 'Program Studi Magister Manajemen', 'Ketua Program Studi', 'active'),
  ('PG646584', 'Marcella Hermawan, M.Sc.', 'Program Studi Magister Manajemen', 'Dosen', 'active'),
  ('PG573119', 'Jessica Santoso, M.T.', 'Program Studi Doktor Ilmu Manajemen', 'Ketua Program Studi', 'active'),
  ('PG590264', 'Dr. Hizkia Hermawan, M.M.', 'Program Studi Doktor Ilmu Manajemen', 'Lektor Kepala', 'active'),
  ('PG635480', 'Kezia Siswanto, Ph.D.', 'Program Studi Arsitektur', 'Ketua Program Studi', 'active'),
  ('PG539055', 'Laurensia Susanto, M.Pd.', 'Program Studi Arsitektur', 'Dosen', 'active'),
  ('PG536355', 'Dr. Clarissa Santoso, Ph.D.', 'Program Studi Arsitektur', 'Dosen', 'active'),
  ('PG664958', 'Ir. Cornelius Sugianto, M.Sc.', 'Program Studi Magister Arsitektur', 'Ketua Program Studi', 'active'),
  ('PG634299', 'Felicia Saputra, Ph.D.', 'Program Studi Magister Arsitektur', 'Lektor Kepala', 'active'),
  ('PG505508', 'Patricia Gunawan, M.Ds.', 'Program Studi Teknik Sipil', 'Ketua Program Studi', 'active'),
  ('PG564161', 'Valencia Tanjung, M.Pd.', 'Program Studi Teknik Sipil', 'Lektor Kepala', 'active'),
  ('PG648486', 'Vincent Saputra, M.Pd.', 'Program Studi Teknik Sipil', 'Dosen', 'active'),
  ('PG507484', 'Hizkia Kurniawan, Ph.D.', 'Program Studi Magister Teknik Sipil', 'Ketua Program Studi', 'active'),
  ('PG620110', 'Dr. Patricia Tanjung, M.Ds.', 'Program Studi Magister Teknik Sipil', 'Dosen', 'active'),
  ('PG659200', 'Ir. Hana Santoso, M.M.', 'Program Studi Ilmu Komunikasi', 'Ketua Program Studi', 'active'),
  ('PG501042', 'Jonathan Salim, M.Sc.', 'Program Studi Ilmu Komunikasi', 'Dosen', 'active'),
  ('PG616473', 'Jonathan Hidayat, Ph.D.', 'Program Studi Bahasa Mandarin', 'Ketua Program Studi', 'active'),
  ('PG663932', 'Dr. Irene Sugianto, M.T.', 'Program Studi Bahasa Mandarin', 'Dosen', 'active'),
  ('PG559617', 'Irene Chandra, M.T.', 'Program Studi Desain Interior', 'Ketua Program Studi', 'active'),
  ('PG600979', 'Irene Hermawan, M.Ds.', 'Program Studi Desain Interior', 'Lektor Kepala', 'active'),
  ('PG577961', 'Irene Saputra, M.Pd.', 'Program Studi Sastra Inggris', 'Ketua Program Studi', 'active'),
  ('PG607594', 'Ir. Theresia Siswanto, M.Sc.', 'Program Studi Sastra Inggris', 'Dosen', 'active'),
  ('PG526649', 'Dr. Nathaniel Setiawan, Ph.D.', 'Program Studi Desain Komunikasi Visual', 'Ketua Program Studi', 'active'),
  ('PG577192', 'Ir. Gabriel Hartono, M.Ds.', 'Program Studi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG657693', 'Benaya Handoko, M.Ds.', 'Program Studi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG661590', 'Priscilla Handoko, M.Ds.', 'Program Studi Magister Sastra', 'Ketua Program Studi', 'active'),
  ('PG681824', 'Agnes Siswanto, M.Ds.', 'Program Studi Magister Sastra', 'Dosen', 'active'),
  ('PG546039', 'Yosef Lim, M.M.', 'Program Studi Teknik Elektro', 'Ketua Program Studi', 'active'),
  ('PG578721', 'Grace Tanjung, M.Pd.', 'Program Studi Teknik Elektro', 'Dosen', 'active'),
  ('PG616609', 'Ir. Aurelia Susanto, Ph.D.', 'Program Studi Teknik Elektro', 'Dosen', 'active'),
  ('PG660389', 'Hizkia Halim, M.Pd.', 'Program Studi Teknik Industri', 'Ketua Program Studi', 'active'),
  ('PG634699', 'Rachel Sutanto, M.Ds.', 'Program Studi Teknik Industri', 'Dosen', 'active'),
  ('PG681184', 'Cornelius Lim, M.Pd.', 'Program Studi Teknik Industri', 'Lektor Kepala', 'active'),
  ('PG591795', 'Jesslyn Hidayat, M.Pd.', 'Program Studi Informatika', 'Ketua Program Studi', 'active'),
  ('PG557816', 'Dr. Evan Liem, M.Ds.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG663266', 'Patricia Handoko, M.Pd.', 'Program Studi Informatika', 'Dosen', 'active'),
  ('PG593383', 'Dr. Nathaniel Kurniawan, M.Ds.', 'Program Studi Informatika', 'Lektor Kepala', 'active'),
  ('PG603179', 'Ir. Kevin Salim, M.Pd.', 'Program Studi Teknik Mesin', 'Ketua Program Studi', 'active'),
  ('PG549679', 'Hana Setiawan, M.Ds.', 'Program Studi Teknik Mesin', 'Dosen', 'active'),
  ('PG619895', 'Evan Hartono, M.Sc.', 'Program Studi Magister Teknik Industri', 'Ketua Program Studi', 'active'),
  ('PG581423', 'Dr. Gabriel Purnomo, M.T.', 'Program Studi Magister Teknik Industri', 'Dosen', 'active'),
  ('PG672720', 'Jessica Kusuma, M.Ds.', 'Program Studi Pendidikan Guru Pendidikan Anak Usia Dini', 'Ketua Program Studi', 'active'),
  ('PG526094', 'Dr. Rachel Siswanto, M.Ds.', 'Program Studi Pendidikan Guru Pendidikan Anak Usia Dini', 'Dosen', 'active'),
  ('PG655830', 'Agnes Hartono, M.M.', 'Program Studi Pendidikan Guru Sekolah Dasar', 'Ketua Program Studi', 'active'),
  ('PG616224', 'Ir. Grace Hermawan, M.M.', 'Program Studi Pendidikan Guru Sekolah Dasar', 'Dosen', 'active'),
  ('PG505398', 'Ir. Grace Purnomo, M.T.', 'Program Studi Kedokteran', 'Ketua Program Studi', 'active'),
  ('PG615813', 'Ir. Daniel Wibowo, M.Ds.', 'Program Studi Kedokteran', 'Dosen', 'active'),
  ('PG695869', 'Dr. Daniel Salim, M.M.', 'Program Studi Kedokteran Gigi', 'Ketua Program Studi', 'active'),
  ('PG612236', 'Dr. Rafael Budiman, M.Pd.', 'Program Studi Kedokteran Gigi', 'Lektor Kepala', 'active')
on conflict (employee_id) do nothing;

-- >>> supabase/seed-supabase/06_kegiatan_2025_2026_a.sql
-- seed-supabase/06_kegiatan_2025_2026_a (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2025/2026 step 1/5: kegiatan 101-120 (all by Program Studi), with peserta.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 101: Program Studi Kedokteran
select pg_temp.keg(101, 'Cultural Exchange Pendidikan Klinis di Kyoto Sangyo University', 76, 29, 'outbound', '2025-09-01', '2025-09-05', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{3,4}', pg_temp.wib('2025-09-18', '11:30'), 'approved', pg_temp.wib('2025-09-28', '15:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(101, 'approved', '{G61236074,G61228465,G61237319,G61246376,G61246402,G61248311,G61258355}', '{}', '{PG615813,PG505398}', pg_temp.wib('2025-09-18', '11:30'), pg_temp.wib('2025-09-28', '15:30'));

-- 102: Program Studi Informatika
select pg_temp.keg(102, 'Pengembangan Kurikulum Kecerdasan Buatan bersama Kyoto Sangyo', 68, 11, 'outbound', '2025-08-04', '2025-09-01', 'online', 'Zoom Meeting', null, 11, '{4,8,17}', pg_temp.wib('2025-09-19', '09:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}, {"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor"}]'::jsonb);

-- 103: Program Studi Akuntansi
select pg_temp.keg(103, 'Cultural Exchange (Inbound) Kyoto Sangyo – Perpajakan Internasional', 6, 29, 'inbound', '2025-09-08', '2025-09-12', 'offline', 'Gedung T PCU', 'ID', 11, '{8,17}', pg_temp.wib('2025-09-22', '14:30'), 'approved', pg_temp.wib('2025-09-30', '12:00'), '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(103, 'approved', '{}', '{X03250305,X03250309,X03250303}', '{PG641614}', pg_temp.wib('2025-09-22', '14:30'), pg_temp.wib('2025-09-30', '12:00'));

-- 104: Program Studi Magister Teknik Industri
select pg_temp.keg(104, 'Seminar Internasional Ergonomi Industri bersama Kyoto Sangyo', 70, 10, 'inbound', '2025-09-22', '2025-09-23', 'online', 'Zoom Meeting', null, 11, '{4,12}', pg_temp.wib('2025-09-26', '08:30'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "speaker"}]'::jsonb);

-- 105: Program Studi Akuntansi
select pg_temp.keg(105, 'Workshop Akuntansi Manajemen bersama Kyoto Sangyo', 6, 35, 'inbound', '2025-09-11', '2025-09-12', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 11, '{8,17}', pg_temp.wib('2025-09-30', '14:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "speaker"}]'::jsonb);

-- 106: Program Studi Informatika
select pg_temp.keg(106, 'Magang Internasional Informatika di Kyoto Sangyo University', 68, 21, 'outbound', '2025-08-25', '2025-09-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,8,9,17}', pg_temp.wib('2025-10-03', '12:45'), 'approved', pg_temp.wib('2025-10-09', '12:30'), '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(106, 'approved', '{B11238162,B11258180,B11228302}', '{}', '{PG591795,PG593383}', pg_temp.wib('2025-10-03', '12:45'), pg_temp.wib('2025-10-09', '12:30'));

-- 107: Program Studi Akuntansi
select pg_temp.keg(107, 'Cultural Exchange (Inbound) Kyoto Sangyo – Akuntansi Manajemen', 6, 29, 'inbound', '2025-09-29', '2025-10-05', 'offline', 'Gedung T PCU', 'ID', 11, '{16,17}', pg_temp.wib('2025-10-12', '08:00'), 'approved', pg_temp.wib('2025-10-24', '10:00'), '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(107, 'approved', '{}', '{X03250303,X03250301,X03250309,X03250307}', '{PG508242}', pg_temp.wib('2025-10-12', '08:00'), pg_temp.wib('2025-10-24', '10:00'));

-- 108: Program Studi Teknik Sipil
select pg_temp.keg(108, 'Short Program Infrastruktur Hijau di Kyoto Sangyo University', 55, 23, 'outbound', '2025-09-22', '2025-10-03', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{6,17}', pg_temp.wib('2025-10-13', '11:00'), 'approved', pg_temp.wib('2025-10-22', '11:30'), '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(108, 'approved', '{A11236394,A11238408,A11248814,A11256435,A11226056}', '{}', '{PG648486,PG564161}', pg_temp.wib('2025-10-13', '11:00'), pg_temp.wib('2025-10-22', '11:30'));

-- 109: Program Studi Kedokteran
select pg_temp.keg(109, 'Studi Ekskursi Kedokteran ke Bandung', 76, 24, 'outbound', '2025-10-20', '2025-10-25', 'offline', 'Bandung', 'ID', 28, '{3,4,6}', pg_temp.wib('2025-10-31', '12:00'), 'approved', pg_temp.wib('2025-11-04', '16:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(109, 'approved', '{G61246402,G61257371,G61236074,G61226627,G61237319,G61246376,G61248311,G61246171,G61228465,G61258355}', '{}', '{PG505398}', pg_temp.wib('2025-10-31', '12:00'), pg_temp.wib('2025-11-04', '16:30'));

-- 110: Program Studi Informatika
select pg_temp.keg(110, 'Staff Exchange Dosen Informatika ke National Taiwan University', 68, 3, 'outbound', '2025-10-20', '2025-10-28', 'offline', 'National Taiwan University', 'TW', 30, '{4}', pg_temp.wib('2025-11-02', '12:45'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Wang Mei-Ling", "institution": "National Taiwan University", "country_code": "TW", "role": "other"}]'::jsonb);

-- 111: Program Studi Akuntansi
select pg_temp.keg(111, 'Immersion Program Akuntansi Forensik di Yonsei University', 6, 22, 'outbound', '2025-10-27', '2025-11-05', 'offline', 'Yonsei University', 'KR', 31, '{4,8,17}', pg_temp.wib('2025-11-10', '12:15'), 'approved', pg_temp.wib('2025-11-20', '09:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(111, 'approved', '{D32226377,D32248238,D32247773,D32227795,D32228656,D32237015,D32236037}', '{}', '{PG641995,PG641614}', pg_temp.wib('2025-11-10', '12:15'), pg_temp.wib('2025-11-20', '09:00'));

-- 112: Program Studi Teknik Mesin
select pg_temp.keg(112, 'Immersion Program Termodinamika Terapan di Kyoto Sangyo University', 69, 22, 'outbound', '2025-10-20', '2025-10-30', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{7,9}', pg_temp.wib('2025-11-11', '15:30'), 'approved', pg_temp.wib('2025-11-23', '13:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(112, 'approved', '{B14238838,B14257666,B14248838,B14248236,B14256141,B14248258,B14258346,B14236733,B14237695,B14238223,B14256589,B14258081}', '{}', '{PG549679,PG603179}', pg_temp.wib('2025-11-11', '15:30'), pg_temp.wib('2025-11-23', '13:30'));

-- 113: Program Studi Desain Komunikasi Visual
select pg_temp.keg(113, 'Workshop Branding Budaya Lokal bersama Yonsei', 63, 35, 'inbound', '2025-10-21', '2025-10-23', 'hybrid', 'Ruang Seminar Gedung W PCU', 'ID', 31, '{4,9,12,17}', pg_temp.wib('2025-11-11', '15:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Kim Soo-yeon", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}, {"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}, {"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}]'::jsonb);

-- 114: Program Studi Sastra Inggris
select pg_temp.keg(114, 'Pengembangan Kurikulum Penerjemahan Sastra bersama Chulalongkorn', 61, 11, 'outbound', '2025-10-20', '2025-11-09', 'online', 'Zoom Meeting', null, 29, '{4,17}', pg_temp.wib('2025-11-15', '14:15'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]'::jsonb);

-- 115: Program Studi Desain Interior
select pg_temp.keg(115, 'Studi Ekskursi Desain Interior ke Yogyakarta', 59, 24, 'outbound', '2025-10-30', '2025-11-01', 'offline', 'Yogyakarta', 'ID', 28, '{4,12}', pg_temp.wib('2025-11-19', '11:45'), 'approved', pg_temp.wib('2025-12-07', '13:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(115, 'approved', '{C22236769,C22237407,C22246629,C22227451,C22237634,C22227224,C22257085,C22228571,C22226908,C22237881,C22247941,C22246153}', '{}', '{PG600979}', pg_temp.wib('2025-11-19', '11:45'), pg_temp.wib('2025-12-07', '13:30'));

-- 116: Program Studi Arsitektur
select pg_temp.keg(116, 'Kuliah Bersama Konservasi Bangunan Bersejarah dengan UGM', 54, 34, 'inbound', '2025-10-31', '2025-10-31', 'offline', 'Gedung Q PCU', 'ID', 28, '{4,13}', pg_temp.wib('2025-11-19', '14:00'), null, null, '{ia,ir}', null, '[{"full_name": "Ir. Yudi Hartanto", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "visiting_lecturer"}]'::jsonb);

-- 117: Program Studi Ilmu Komunikasi
select pg_temp.keg(117, 'Cultural Exchange (Inbound) Chulalongkorn – Public Relations Global', 57, 29, 'inbound', '2025-11-10', '2025-11-15', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 29, '{5,16}', pg_temp.wib('2025-11-25', '14:30'), 'approved', pg_temp.wib('2025-12-10', '14:30'), '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(117, 'approved', '{}', '{X03250349,X03250347,X03250343}', '{PG501042,PG659200}', pg_temp.wib('2025-11-25', '14:30'), pg_temp.wib('2025-12-10', '14:30'));

-- 118: Program Studi Informatika
select pg_temp.keg(118, 'Cultural Exchange (Inbound) Yonsei – Komputasi Awan', 68, 29, 'inbound', '2025-11-10', '2025-11-17', 'offline', 'Gedung P PCU', 'ID', 31, '{4}', pg_temp.wib('2025-12-04', '12:45'), 'approved', pg_temp.wib('2025-12-10', '15:30'), '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(118, 'approved', '{}', '{X03250355,X03250353,X03250357,X03250359}', '{PG663266,PG593383}', pg_temp.wib('2025-12-04', '12:45'), pg_temp.wib('2025-12-10', '15:30'));

-- 119: Program Studi Kedokteran Gigi
select pg_temp.keg(119, 'Academic Visit Kedokteran Gigi ke Universitas Gadjah Mada', 74, 27, 'outbound', '2025-12-03', '2025-12-04', 'hybrid', 'Universitas Gadjah Mada', 'ID', 28, '{3,6}', pg_temp.wib('2025-12-06', '13:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 120: Program Studi Manajemen
select pg_temp.keg(120, 'Studi Ekskursi Manajemen ke National Taiwan University, Taipei', 5, 24, 'outbound', '2025-11-10', '2025-11-15', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{9}', pg_temp.wib('2025-12-06', '16:45'), 'approved', pg_temp.wib('2025-12-09', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(120, 'approved', '{D31236401,D31237541,D31248243,D31237627,D31228357,D31258883,D31248545,D31237888,D31256312}', '{}', '{PG626211}', pg_temp.wib('2025-12-06', '16:45'), pg_temp.wib('2025-12-09', '13:00'));

-- >>> supabase/seed-supabase/06_kegiatan_2025_2026_b.sql
-- seed-supabase/06_kegiatan_2025_2026_b (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2025/2026 step 2/5: kegiatan 121-140 (all by Program Studi), with peserta.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 121: Program Studi Teknik Mesin
select pg_temp.keg(121, 'Studi Ekskursi Teknik Mesin ke Malang', 69, 24, 'outbound', '2025-11-23', '2025-11-25', 'offline', 'Malang', 'ID', 28, '{7,12,17}', pg_temp.wib('2025-12-07', '11:15'), 'approved', pg_temp.wib('2025-12-14', '12:00'), '{ia,ir}', null, '[{"full_name": "Dewi Anggraini, S.T., M.B.A.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(121, 'approved', '{B14256141,B14248838,B14256589,B14238838,B14237695,B14258081,B14236733,B14238223,B14258346,B14248236,B14257666,B14248258}', '{}', '{PG603179}', pg_temp.wib('2025-12-07', '11:15'), pg_temp.wib('2025-12-14', '12:00'));

-- 122: Program Studi Kedokteran Gigi
select pg_temp.keg(122, 'Magang Industri Kedokteran Gigi di Universitas Gadjah Mada', 74, 21, 'outbound', '2025-11-03', '2025-12-14', 'offline', 'Universitas Gadjah Mada', 'ID', 28, '{3}', pg_temp.wib('2025-12-17', '13:30'), 'approved', pg_temp.wib('2025-12-28', '14:30'), '{ia,ir}', null, '[{"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(122, 'approved', '{G62247977,G62238105,G62246895}', '{}', '{PG695869,PG612236}', pg_temp.wib('2025-12-17', '13:30'), pg_temp.wib('2025-12-28', '14:30'));

-- 123: Program Studi Desain Komunikasi Visual
select pg_temp.keg(123, 'Immersion Program Desain Berkelanjutan di Chulalongkorn University', 63, 22, 'outbound', '2025-11-17', '2025-11-28', 'offline', 'Chulalongkorn University', 'TH', 29, '{4,12}', pg_temp.wib('2025-12-19', '10:15'), 'approved', pg_temp.wib('2025-12-29', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(123, 'approved', '{C21228976,C21246699,C21236260,C21237469,C21226735,C21248397,C21236671,C21228109,C21247016,C21226359,C21227424,C21246495}', '{}', '{PG526649,PG657693}', pg_temp.wib('2025-12-19', '10:15'), pg_temp.wib('2025-12-29', '10:00'));

-- 124: Program Studi Arsitektur
select pg_temp.keg(124, 'Kuliah Bersama Hunian Terjangkau dengan Chulalongkorn', 54, 34, 'inbound', '2025-10-30', '2025-10-31', 'hybrid', 'Ruang Seminar Gedung W PCU', 'ID', 29, '{4,11,17}', pg_temp.wib('2025-12-25', '14:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "visiting_lecturer"}]'::jsonb);

-- 125: Program Studi Akuntansi
select pg_temp.keg(125, 'Magang Internasional Akuntansi di Yonsei University', 6, 21, 'outbound', '2025-10-27', '2025-12-07', 'offline', 'Yonsei University', 'KR', 31, '{4,17}', pg_temp.wib('2025-12-26', '08:00'), 'approved', pg_temp.wib('2026-01-11', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(125, 'approved', '{D32257684,D32257260}', '{}', '{PG641995,PG641614}', pg_temp.wib('2025-12-26', '08:00'), pg_temp.wib('2026-01-11', '13:00'));

-- 126: Program Studi Desain Interior
select pg_temp.keg(126, 'Pengembangan Kurikulum Desain Ruang Publik bersama UGM', 59, 11, 'outbound', '2025-10-27', '2025-12-10', 'online', 'Zoom Meeting', null, 28, '{4,11,17}', pg_temp.wib('2025-12-27', '12:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Rina Kartikasari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other"}, {"full_name": "Dr. Ayu Lestari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other"}]'::jsonb);

-- 127: Program Studi Sastra Inggris
select pg_temp.keg(127, 'Workshop Penerjemahan Sastra bersama NTU', 61, 35, 'inbound', '2025-12-19', '2025-12-20', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 30, '{4}', pg_temp.wib('2026-01-06', '16:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}, {"full_name": "Dr. Huang Jun-Wei", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]'::jsonb);

-- 128: Program Studi Manajemen
select pg_temp.keg(128, 'Staff Exchange Dosen Manajemen ke Chulalongkorn University', 5, 3, 'outbound', '2025-12-08', '2025-12-20', 'hybrid', 'Chulalongkorn University', 'TH', 29, '{8}', pg_temp.wib('2026-01-10', '09:30'), null, null, '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]'::jsonb);

-- 129: Program Studi Manajemen
select pg_temp.keg(129, 'Studi Ekskursi Manajemen ke Yonsei University, Seoul', 5, 24, 'outbound', '2025-12-15', '2025-12-22', 'offline', 'Yonsei University, Seoul', 'KR', 31, '{8,12}', pg_temp.wib('2026-01-12', '11:30'), 'approved', pg_temp.wib('2026-01-20', '12:00'), '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(129, 'approved', '{D31237873,D31248243,D31248761,D31227308,D31236401,D31246583,D31237627,D31227742,D31248101,D31248545,D31247059}', '{}', '{PG670883}', pg_temp.wib('2026-01-12', '11:30'), pg_temp.wib('2026-01-20', '12:00'));

-- 130: Program Studi Akuntansi
select pg_temp.keg(130, 'Workshop Akuntansi Forensik bersama Astra', 6, 35, 'inbound', '2026-01-05', '2026-01-06', 'offline', 'Gedung Q PCU', 'ID', 12, '{8}', pg_temp.wib('2026-01-13', '16:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}, {"full_name": "Dr. Rina Kartikasari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 131: Program Studi Akuntansi
select pg_temp.keg(131, 'Short Program (Inbound) Chulalongkorn – Audit Berbasis Data', 6, 23, 'inbound', '2025-12-22', '2026-01-06', 'offline', 'Gedung P PCU', 'ID', 29, '{16}', pg_temp.wib('2026-01-13', '16:45'), 'approved', pg_temp.wib('2026-01-29', '16:00'), '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(131, 'approved', '{}', '{X03250345,X03250341,X03250343,X03250349,X03250347}', '{PG641614}', pg_temp.wib('2026-01-13', '16:45'), pg_temp.wib('2026-01-29', '16:00'));

-- 132: Program Studi Magister Manajemen
select pg_temp.keg(132, 'Staff Exchange Dosen Magister Manajemen ke Chulalongkorn University', 48, 3, 'outbound', '2025-12-22', '2026-01-02', 'hybrid', 'Chulalongkorn University', 'TH', 29, '{4,9}', pg_temp.wib('2026-01-14', '12:15'), null, null, '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other"}, {"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other"}]'::jsonb);

-- 133: Program Studi Teknik Mesin
select pg_temp.keg(133, 'Immersion Program Kendaraan Listrik di National Taiwan University', 69, 22, 'outbound', '2025-12-29', '2026-01-06', 'offline', 'National Taiwan University', 'TW', 30, '{12,17}', pg_temp.wib('2026-01-25', '11:00'), 'approved', pg_temp.wib('2026-02-05', '14:00'), '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Wang Mei-Ling", "institution": "National Taiwan University", "country_code": "TW", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(133, 'approved', '{B14238223,B14236733,B14237695,B14257666,B14258081,B14248236,B14248838}', '{}', '{PG603179}', pg_temp.wib('2026-01-25', '11:00'), pg_temp.wib('2026-02-05', '14:00'));

-- 134: Program Studi Bahasa Mandarin
select pg_temp.keg(134, 'MBKM Pertukaran Mahasiswa Bahasa Mandarin di Universitas Gadjah Mada', 58, 38, 'outbound', '2025-10-20', '2026-01-22', 'offline', 'Universitas Gadjah Mada', 'ID', 28, '{10,17}', pg_temp.wib('2026-01-25', '12:45'), 'approved', pg_temp.wib('2026-02-12', '09:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(134, 'approved', '{E43247625,E43228663,E43238216}', '{}', '{}', pg_temp.wib('2026-01-25', '12:45'), pg_temp.wib('2026-02-12', '09:00'));

-- 135: Program Studi Pendidikan Guru Sekolah Dasar
select pg_temp.keg(135, 'Academic Exchange (Inbound) Kyoto Sangyo – Literasi Dasar', 73, 28, 'inbound', '2025-10-20', '2026-01-22', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4}', pg_temp.wib('2026-01-26', '10:45'), 'approved', pg_temp.wib('2026-02-03', '13:00'), '{ia,ir}', null, '[{"full_name": "Dr. Hiroshi Kato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(135, 'approved', '{}', '{X03250301,X03250311,X03250305,X03250307}', '{}', pg_temp.wib('2026-01-26', '10:45'), pg_temp.wib('2026-02-03', '13:00'));

-- 136: Program Studi Ilmu Komunikasi
select pg_temp.keg(136, 'Academic Exchange (Inbound) Kyoto Sangyo – Komunikasi Krisis', 57, 28, 'inbound', '2025-10-20', '2026-01-25', 'offline', 'Gedung T PCU', 'ID', 11, '{4,5}', pg_temp.wib('2026-01-28', '10:45'), 'approved', pg_temp.wib('2026-02-15', '10:30'), '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(136, 'approved', '{}', '{X03250309,X03250303}', '{PG659200,PG501042}', pg_temp.wib('2026-01-28', '10:45'), pg_temp.wib('2026-02-15', '10:30'));

-- 137: Program Studi Informatika
select pg_temp.keg(137, 'Short Program Rekayasa Perangkat Lunak di University of Amsterdam', 68, 23, 'outbound', '2026-01-12', '2026-01-26', 'offline', 'University of Amsterdam', 'NL', 32, '{4,8}', pg_temp.wib('2026-01-29', '09:15'), 'approved', pg_temp.wib('2026-02-06', '11:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(137, 'approved', '{B11258007,B11228302,B11257605,B11247302,B11238382,B11246879,B11258180}', '{}', '{}', pg_temp.wib('2026-01-29', '09:15'), pg_temp.wib('2026-02-06', '11:00'));

-- 138: Program Studi Informatika
select pg_temp.keg(138, 'Academic Exchange (Inbound) Amsterdam – Kecerdasan Buatan', 68, 28, 'inbound', '2025-10-20', '2026-01-26', 'offline', 'Gedung T PCU', 'ID', 32, '{4,8}', pg_temp.wib('2026-01-31', '10:30'), 'approved', pg_temp.wib('2026-02-06', '14:30'), '{ia,ir}', null, '[{"full_name": "Dr. Bram Janssen", "institution": "University of Amsterdam", "country_code": "NL", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(138, 'approved', '{}', '{X03250323,X03250329,X03250325,X03250327}', '{}', pg_temp.wib('2026-01-31', '10:30'), pg_temp.wib('2026-02-06', '14:30'));

-- 139: Program Studi Desain Komunikasi Visual
select pg_temp.keg(139, 'Riset Bersama Branding Budaya Lokal dengan University of Amsterdam', 63, 4, 'outbound', '2025-11-17', '2026-01-19', 'hybrid', 'University of Amsterdam', 'NL', 32, '{4,11}', pg_temp.wib('2026-01-31', '13:30'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Pieter van Dijk", "institution": "University of Amsterdam", "country_code": "NL", "role": "researcher"}, {"full_name": "Dr. Anouk Smit", "institution": "University of Amsterdam", "country_code": "NL", "role": "researcher"}]'::jsonb);

-- 140: Program Studi Desain Komunikasi Visual
select pg_temp.keg(140, 'Study Abroad Branding Budaya Lokal di University of Amsterdam', 63, 20, 'outbound', '2025-10-20', '2026-01-31', 'offline', 'University of Amsterdam', 'NL', 32, '{4,12}', pg_temp.wib('2026-02-02', '10:30'), 'approved', pg_temp.wib('2026-02-14', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(140, 'approved', '{C21258635,C21238527,C21237086}', '{}', '{}', pg_temp.wib('2026-02-02', '10:30'), pg_temp.wib('2026-02-14', '13:00'));

-- >>> supabase/seed-supabase/06_kegiatan_2025_2026_c.sql
-- seed-supabase/06_kegiatan_2025_2026_c (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2025/2026 step 3/5: kegiatan 141-160 (all by Program Studi), with peserta.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 141: Program Studi Informatika
select pg_temp.keg(141, 'Short Program Keamanan Siber di Chulalongkorn University', 68, 23, 'outbound', '2025-12-29', '2026-01-18', 'offline', 'Chulalongkorn University', 'TH', 29, '{9}', pg_temp.wib('2026-02-04', '09:00'), 'approved', pg_temp.wib('2026-02-15', '11:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(141, 'approved', '{B11248139,B11236858,B11247339,B11238162,B11237976,B11238934}', '{}', '{PG557816}', pg_temp.wib('2026-02-04', '09:00'), pg_temp.wib('2026-02-15', '11:30'));

-- 142: Program Studi Arsitektur
select pg_temp.keg(142, 'Pengembangan Kurikulum Desain Kota Pesisir bersama Astra', 54, 11, 'outbound', '2026-01-05', '2026-01-25', 'online', 'Zoom Meeting', null, 12, '{4,9,13}', pg_temp.wib('2026-02-07', '15:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Rina Kartikasari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 143: Program Studi Informatika
select pg_temp.keg(143, 'Workshop Rekayasa Perangkat Lunak bersama Chulalongkorn', 68, 35, 'inbound', '2026-01-27', '2026-01-29', 'offline', 'Auditorium Radius Prawiro PCU', 'ID', 29, '{4,9,17}', pg_temp.wib('2026-02-08', '13:15'), null, null, '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]'::jsonb);

-- 144: Program Studi Akuntansi
select pg_temp.keg(144, 'Pengembangan Kurikulum Akuntansi Forensik bersama Yonsei', 6, 11, 'outbound', '2025-12-29', '2026-01-21', 'online', 'Zoom Meeting', null, 31, '{16,17}', pg_temp.wib('2026-02-09', '12:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "staff_visitor"}]'::jsonb);

-- 145: Program Studi Pendidikan Guru Pendidikan Anak Usia Dini
select pg_temp.keg(145, 'Kuliah Bersama Pendidikan Inklusif dengan Yonsei', 72, 34, 'inbound', '2026-02-04', '2026-02-04', 'hybrid', 'Gedung T PCU', 'ID', 31, '{10,17}', pg_temp.wib('2026-02-11', '10:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "visiting_lecturer"}]'::jsonb);

-- 146: Program Studi Manajemen
select pg_temp.keg(146, 'Pengabdian Masyarakat Strategi Bisnis Asia bersama UGM', 5, 40, 'outbound', '2026-01-22', '2026-01-25', 'hybrid', 'Kampung Batik Jetis', 'ID', 28, '{4,8,17}', pg_temp.wib('2026-02-13', '13:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 147: Program Studi Arsitektur
select pg_temp.keg(147, 'Cultural Exchange (Inbound) Kyoto Sangyo – Desain Kota Pesisir', 54, 29, 'inbound', '2026-02-02', '2026-02-10', 'offline', 'Gedung P PCU', 'ID', 11, '{4,11,13}', pg_temp.wib('2026-02-14', '10:30'), 'approved', pg_temp.wib('2026-02-19', '14:30'), '{ia,ir}', null, '[{"full_name": "Dr. Hiroshi Kato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(147, 'approved', '{}', '{X03250303,X03250307,X04260310,X04260306,X03250309}', '{PG635480,PG539055}', pg_temp.wib('2026-02-14', '10:30'), pg_temp.wib('2026-02-19', '14:30'));

-- 148: Program Studi Manajemen
select pg_temp.keg(148, 'Student Exchange Bisnis Keluarga di National Taiwan University', 5, 2, 'outbound', '2025-10-20', '2026-01-28', 'offline', 'National Taiwan University', 'TW', 30, '{4,8}', pg_temp.wib('2026-02-18', '14:00'), 'approved', pg_temp.wib('2026-02-28', '09:30'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(148, 'approved', '{D31258938,D31256420}', '{}', '{PG643269}', pg_temp.wib('2026-02-18', '14:00'), pg_temp.wib('2026-02-28', '09:30'));

-- 149: Program Studi Manajemen
select pg_temp.keg(149, 'Seminar Internasional Manajemen Rantai Pasok bersama UGM', 5, 10, 'inbound', '2026-02-10', '2026-02-10', 'online', 'Zoom Meeting', null, 28, '{8,12}', pg_temp.wib('2026-02-19', '14:45'), null, null, '{ia,ir}', null, '[{"full_name": "Hendro Saputro, S.E., M.M.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}, {"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 150: Program Studi Magister Teknik Sipil
select pg_temp.keg(150, 'Staff Exchange Dosen Magister Teknik Sipil ke PT Astra International Tbk', 56, 3, 'outbound', '2026-02-16', '2026-02-20', 'offline', 'PT Astra International Tbk', 'ID', 12, '{6}', pg_temp.wib('2026-02-27', '15:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 151: Program Studi Akuntansi
select pg_temp.keg(151, 'Kuliah Tamu Perpajakan Internasional dari Chulalongkorn University', 6, 15, 'inbound', '2026-02-14', '2026-02-15', 'online', 'Zoom Meeting', null, 29, '{4,8,16,17}', pg_temp.wib('2026-03-02', '10:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]'::jsonb);

-- 152: Program Studi Arsitektur
select pg_temp.keg(152, 'Kuliah Tamu Konservasi Bangunan Bersejarah dari National University of Singapore', 54, 15, 'inbound', '2026-03-05', '2026-03-06', 'offline', 'Gedung Q PCU', 'ID', 19, '{4,11,17}', pg_temp.wib('2026-03-26', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 153: Program Studi Teknik Mesin
select pg_temp.keg(153, 'Kuliah Bersama Manufaktur Aditif dengan Chulalongkorn', 69, 34, 'inbound', '2026-03-21', '2026-03-21', 'offline', 'Gedung P PCU', 'ID', 29, '{4,7,12}', pg_temp.wib('2026-03-30', '13:15'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "visiting_lecturer"}]'::jsonb);

-- 154: Program Studi Kedokteran
select pg_temp.keg(154, 'Cultural Exchange (Inbound) NTU – Telemedisin', 76, 29, 'inbound', '2026-03-23', '2026-03-30', 'offline', 'Gedung Q PCU', 'ID', 15, '{4}', pg_temp.wib('2026-04-06', '09:30'), 'approved', pg_temp.wib('2026-04-17', '14:30'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(154, 'approved', '{}', '{X03250313,X04260316,X04260320,X03250317}', '{PG615813,PG505398}', pg_temp.wib('2026-04-06', '09:30'), pg_temp.wib('2026-04-17', '14:30'));

-- 155: Program Studi Ilmu Komunikasi
select pg_temp.keg(155, 'Staff Exchange Dosen Ilmu Komunikasi ke University of Amsterdam', 57, 3, 'outbound', '2026-03-23', '2026-03-28', 'hybrid', 'University of Amsterdam', 'NL', 17, '{5,16}', pg_temp.wib('2026-04-09', '10:15'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Bram Janssen", "institution": "University of Amsterdam", "country_code": "NL", "role": "other"}, {"full_name": "Dr. Anouk Smit", "institution": "University of Amsterdam", "country_code": "NL", "role": "other"}]'::jsonb);

-- 156: Program Studi Desain Interior
select pg_temp.keg(156, 'Magang Internasional Desain Interior di Yonsei University', 59, 21, 'outbound', '2026-02-09', '2026-03-27', 'offline', 'Yonsei University', 'KR', 31, '{4,9,12}', pg_temp.wib('2026-04-14', '13:15'), 'approved', pg_temp.wib('2026-04-27', '12:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(156, 'approved', '{C22246629,C22246153}', '{}', '{PG600979,PG559617}', pg_temp.wib('2026-04-14', '13:15'), pg_temp.wib('2026-04-27', '12:00'));

-- 157: Program Studi Informatika
select pg_temp.keg(157, 'Academic Visit Informatika ke PT Astra International Tbk', 68, 27, 'outbound', '2026-04-17', '2026-04-17', 'offline', 'PT Astra International Tbk', 'ID', 23, '{4,9}', pg_temp.wib('2026-04-20', '14:15'), null, null, '{ia,ir}', null, '[{"full_name": "Ir. Dimas Prakoso, M.T.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}, {"full_name": "Hendro Saputro, S.E., M.M.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 158: Program Studi Arsitektur
select pg_temp.keg(158, 'Kuliah Bersama Konservasi Bangunan Bersejarah dengan Astra', 54, 34, 'inbound', '2026-04-06', '2026-04-07', 'hybrid', 'Gedung P PCU', 'ID', 12, '{4,13}', pg_temp.wib('2026-04-25', '14:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dewi Anggraini, S.T., M.B.A.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "visiting_lecturer"}]'::jsonb);

-- 159: Program Studi Teknik Mesin
select pg_temp.keg(159, 'Magang Internasional Teknik Mesin di University of Amsterdam', 69, 21, 'outbound', '2026-03-02', '2026-04-12', 'offline', 'University of Amsterdam', 'NL', 17, '{7}', pg_temp.wib('2026-04-28', '11:30'), 'approved', pg_temp.wib('2026-05-14', '13:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(159, 'approved', '{B14256141,B14237695,B14248258,B14257666}', '{}', '{PG603179}', pg_temp.wib('2026-04-28', '11:30'), pg_temp.wib('2026-05-14', '13:30'));

-- 160: Program Studi Arsitektur
select pg_temp.keg(160, 'Magang Internasional Arsitektur di National University of Singapore', 54, 21, 'outbound', '2026-03-09', '2026-04-13', 'offline', 'National University of Singapore', 'SG', 19, '{9,11}', pg_temp.wib('2026-05-02', '09:30'), 'approved', pg_temp.wib('2026-05-05', '16:00'), '{ia,ir}', null, '[{"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(160, 'approved', '{A12247377,A12227569}', '{}', '{PG635480,PG539055}', pg_temp.wib('2026-05-02', '09:30'), pg_temp.wib('2026-05-05', '16:00'));

-- >>> supabase/seed-supabase/06_kegiatan_2025_2026_d.sql
-- seed-supabase/06_kegiatan_2025_2026_d (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2025/2026 step 4/5: kegiatan 161-180 (all by Program Studi), with peserta.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 161: Program Studi Teknik Elektro
select pg_temp.keg(161, 'Pengembangan Kurikulum Internet of Things bersama Astra', 65, 11, 'outbound', '2026-04-13', '2026-05-14', 'offline', 'PT Astra International Tbk', 'ID', 12, '{13,17}', pg_temp.wib('2026-05-16', '08:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}, {"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 162: Program Studi Ilmu Komunikasi
select pg_temp.keg(162, 'Study Abroad Komunikasi Krisis di Kyoto Sangyo University', 57, 20, 'outbound', '2026-02-16', '2026-05-16', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,16}', pg_temp.wib('2026-05-25', '14:15'), 'approved', pg_temp.wib('2026-05-30', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(162, 'approved', '{E42257788}', '{}', '{}', pg_temp.wib('2026-05-25', '14:15'), pg_temp.wib('2026-05-30', '13:00'));

-- 163: Program Studi Manajemen
select pg_temp.keg(163, 'Academic Visit Manajemen ke PT Astra International Tbk', 5, 27, 'outbound', '2026-05-11', '2026-05-12', 'offline', 'PT Astra International Tbk', 'ID', 12, '{8,9}', pg_temp.wib('2026-06-01', '12:15'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 164: Program Studi Desain Interior
select pg_temp.keg(164, 'Cultural Exchange (Inbound) NTU – Ilustrasi dan Narasi Visual', 59, 29, 'inbound', '2026-05-11', '2026-05-18', 'offline', 'Gedung P PCU', 'ID', 15, '{4,9,12}', pg_temp.wib('2026-06-02', '12:00'), 'approved', pg_temp.wib('2026-06-20', '10:00'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(164, 'approved', '{}', '{X04260314,X03250319,X03250315,X04260318,X04260322}', '{PG600979}', pg_temp.wib('2026-06-02', '12:00'), pg_temp.wib('2026-06-20', '10:00'));

-- 165: Program Studi Kedokteran
select pg_temp.keg(165, 'Magang Internasional Kedokteran di University of Amsterdam', 76, 21, 'outbound', '2026-03-30', '2026-05-12', 'offline', 'University of Amsterdam', 'NL', 17, '{4,6,17}', pg_temp.wib('2026-06-02', '14:15'), 'approved', pg_temp.wib('2026-06-13', '16:30'), '{ia,ir}', null, '[{"full_name": "Prof. Pieter van Dijk", "institution": "University of Amsterdam", "country_code": "NL", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(165, 'approved', '{G61257371,G61228465}', '{}', '{}', pg_temp.wib('2026-06-02', '14:15'), pg_temp.wib('2026-06-13', '16:30'));

-- 166: Program Studi Pendidikan Guru Sekolah Dasar
select pg_temp.keg(166, 'Workshop Pendidikan Inklusif bersama Astra', 73, 35, 'inbound', '2026-05-30', '2026-05-31', 'offline', 'Gedung Q PCU', 'ID', 23, '{4,5,17}', pg_temp.wib('2026-06-02', '15:00'), null, null, '{ia,ir}', null, '[{"full_name": "Hendro Saputro, S.E., M.M.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 167: Program Studi Bahasa Mandarin
select pg_temp.keg(167, 'Studi Ekskursi Bahasa Mandarin ke Bandung', 58, 24, 'outbound', '2026-05-21', '2026-05-24', 'offline', 'Bandung', 'ID', 28, '{4,17}', pg_temp.wib('2026-06-03', '12:15'), 'approved', pg_temp.wib('2026-06-16', '12:00'), '{ia,ir}', null, '[{"full_name": "Prof. Bambang Wicaksono", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(167, 'approved', '{E43237395,E43236934,E43257300,E43248713,E43228663,E43238216,E43258937,E43246366,E43237289,E43247625}', '{}', '{PG616473,PG663932}', pg_temp.wib('2026-06-03', '12:15'), pg_temp.wib('2026-06-16', '12:00'));

-- 168: Program Studi Arsitektur
select pg_temp.keg(168, 'Studi Ekskursi Arsitektur ke National University of Singapore, Singapura', 54, 24, 'outbound', '2026-04-20', '2026-04-24', 'offline', 'National University of Singapore, Singapura', 'SG', 19, '{9}', pg_temp.wib('2026-06-03', '12:30'), 'approved', pg_temp.wib('2026-06-19', '14:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(168, 'approved', '{A12238117,A12248128,A12248183,A12256710,A12246197,A12226528,A12247377,A12256772,A12248533,A12236715,A12238779}', '{}', '{PG536355}', pg_temp.wib('2026-06-03', '12:30'), pg_temp.wib('2026-06-19', '14:00'));

-- 169: Program Studi Akuntansi
select pg_temp.keg(169, 'Magang Internasional Akuntansi di Chulalongkorn University', 6, 21, 'outbound', '2026-04-20', '2026-05-30', 'offline', 'Chulalongkorn University', 'TH', 29, '{4,16,17}', pg_temp.wib('2026-06-03', '15:00'), 'revision_requested', pg_temp.wib('2026-06-12', '11:30'), '{ia,ir}', 'Mohon lengkapi daftar dosen pendamping sesuai surat tugas.', '[]'::jsonb);
select pg_temp.peserta(169, 'revision_requested', '{D32226377,D32258446,D32247516,D32237015}', '{}', '{PG508242,PG641614}', pg_temp.wib('2026-06-03', '15:00'), pg_temp.wib('2026-06-12', '11:30'));

-- 170: Program Studi Teknik Elektro
select pg_temp.keg(170, 'Cultural Exchange Kendali Cerdas di University of Amsterdam', 65, 29, 'outbound', '2026-05-18', '2026-05-22', 'offline', 'University of Amsterdam', 'NL', 32, '{4,7,9}', pg_temp.wib('2026-06-06', '13:00'), 'approved', pg_temp.wib('2026-06-14', '11:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(170, 'approved', '{B12257643,B12248967,B12236482,B12247379,B12256522,B12248934,B12237202,B12257098,B12238289}', '{}', '{PG546039,PG578721}', pg_temp.wib('2026-06-06', '13:00'), pg_temp.wib('2026-06-14', '11:00'));

-- 171: Program Studi Teknik Elektro
select pg_temp.keg(171, 'Cultural Exchange (Inbound) Yonsei – Elektronika Daya', 65, 29, 'inbound', '2026-05-25', '2026-05-29', 'offline', 'Gedung Q PCU', 'ID', 31, '{4,7,13}', pg_temp.wib('2026-06-08', '09:00'), 'approved', pg_temp.wib('2026-06-18', '11:30'), '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(171, 'approved', '{}', '{X03250355,X04260356,X03250353,X04260352,X03250357}', '{PG546039,PG578721}', pg_temp.wib('2026-06-08', '09:00'), pg_temp.wib('2026-06-18', '11:30'));

-- 172: Program Studi Bahasa Mandarin
select pg_temp.keg(172, 'Short Program (Inbound) Kyoto Sangyo – Linguistik Terapan', 58, 23, 'inbound', '2026-05-18', '2026-05-29', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,10}', pg_temp.wib('2026-06-11', '15:30'), 'approved', pg_temp.wib('2026-06-24', '13:00'), '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(172, 'approved', '{}', '{X04260308,X04260310,X04260312,X04260304}', '{PG663932,PG616473}', pg_temp.wib('2026-06-11', '15:30'), pg_temp.wib('2026-06-24', '13:00'));

-- 173: Program Studi Magister Manajemen
select pg_temp.keg(173, 'Riset Bersama Bisnis Keluarga dengan PT Unilever Indonesia Tbk', 48, 4, 'outbound', '2026-04-06', '2026-06-09', 'hybrid', 'PT Unilever Indonesia Tbk', 'ID', 21, '{4,12,17}', pg_temp.wib('2026-06-13', '10:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "researcher"}, {"full_name": "Ir. Yudi Hartanto", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "researcher"}]'::jsonb);

-- 174: Program Studi Magister Arsitektur
select pg_temp.keg(174, 'Seminar Internasional Arsitektur Tropis bersama Astra', 53, 10, 'inbound', '2026-05-26', '2026-05-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 23, '{4,13}', pg_temp.wib('2026-06-14', '08:15'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 175: Program Studi Magister Teknik Sipil
select pg_temp.keg(175, 'Magang Industri Magister Teknik Sipil di PT Astra International Tbk', 56, 21, 'outbound', '2026-04-20', '2026-05-31', 'offline', 'PT Astra International Tbk', 'ID', 23, '{11}', pg_temp.wib('2026-06-15', '10:30'), 'approved', pg_temp.wib('2026-06-30', '15:30'), '{ia,ir}', null, '[{"full_name": "Hendro Saputro, S.E., M.M.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(175, 'approved', '{A14248811,A14246094,A14247655,A14257290,A14248809,A14248433}', '{}', '{}', pg_temp.wib('2026-06-15', '10:30'), pg_temp.wib('2026-06-30', '15:30'));

-- 176: Program Studi Akuntansi
select pg_temp.keg(176, 'Magang Industri Akuntansi di PT Unilever Indonesia Tbk', 6, 21, 'outbound', '2026-04-13', '2026-06-03', 'offline', 'PT Unilever Indonesia Tbk', 'ID', 21, '{16}', pg_temp.wib('2026-06-17', '09:30'), 'approved', pg_temp.wib('2026-07-05', '12:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(176, 'approved', '{D32227188,D32248005,D32227795,D32257463,D32237743}', '{}', '{PG641614}', pg_temp.wib('2026-06-17', '09:30'), pg_temp.wib('2026-07-05', '12:30'));

-- 177: Program Studi Manajemen
select pg_temp.keg(177, 'Kuliah Bersama Manajemen SDM Global dengan NUS', 5, 34, 'inbound', '2026-06-12', '2026-06-13', 'hybrid', 'Gedung Q PCU', 'ID', 19, '{4,9,12,17}', pg_temp.wib('2026-06-17', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "visiting_lecturer"}]'::jsonb);

-- 178: Program Studi Manajemen
select pg_temp.keg(178, 'Studi Ekskursi Manajemen ke Yogyakarta', 5, 24, 'outbound', '2026-06-07', '2026-06-09', 'offline', 'Yogyakarta', 'ID', 12, '{4,9,17}', pg_temp.wib('2026-06-19', '16:00'), 'approved', pg_temp.wib('2026-07-07', '14:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(178, 'approved', '{D31237873,D31248101,D31256312,D31237888,D31247028,D31236101,D31228283,D31248402,D31258883,D31227308}', '{}', '{PG661938}', pg_temp.wib('2026-06-19', '16:00'), pg_temp.wib('2026-07-07', '14:00'));

-- 179: Program Studi Manajemen
select pg_temp.keg(179, 'Academic Exchange (Inbound) Chulalongkorn – Manajemen Rantai Pasok', 5, 28, 'inbound', '2026-02-23', '2026-06-03', 'offline', 'Gedung P PCU', 'ID', 29, '{4,12}', pg_temp.wib('2026-06-23', '14:30'), 'approved', pg_temp.wib('2026-07-08', '16:00'), '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(179, 'approved', '{}', '{X04260344,X04260346,X04260342}', '{}', pg_temp.wib('2026-06-23', '14:30'), pg_temp.wib('2026-07-08', '16:00'));

-- 180: Program Studi Teknik Mesin
select pg_temp.keg(180, 'Studi Ekskursi Teknik Mesin ke Kyoto Sangyo University, Kyoto', 69, 24, 'outbound', '2026-05-31', '2026-06-03', 'offline', 'Kyoto Sangyo University, Kyoto', 'JP', 11, '{4,12}', pg_temp.wib('2026-06-23', '16:00'), 'approved', pg_temp.wib('2026-07-10', '12:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(180, 'approved', '{B14256589,B14248838,B14238223,B14236733,B14256141,B14257666,B14258081,B14237695,B14248236,B14238838}', '{}', '{PG603179}', pg_temp.wib('2026-06-23', '16:00'), pg_temp.wib('2026-07-10', '12:00'));

-- >>> supabase/seed-supabase/06_kegiatan_2025_2026_e.sql
-- seed-supabase/06_kegiatan_2025_2026_e (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2025/2026 step 5/5: kegiatan 181-200 (all by Program Studi), with peserta.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 181: Program Studi Manajemen
select pg_temp.keg(181, 'Workshop Manajemen Rantai Pasok bersama NUS', 5, 35, 'inbound', '2026-06-21', '2026-06-23', 'hybrid', 'Kampus PCU Siwalankerto', 'ID', 19, '{9}', pg_temp.wib('2026-06-26', '08:30'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}, {"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 182: Program Studi Teknik Sipil
select pg_temp.keg(182, 'Academic Exchange (Inbound) Kyoto Sangyo – Manajemen Konstruksi', 55, 28, 'inbound', '2026-03-16', '2026-06-14', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 11, '{6,11}', pg_temp.wib('2026-06-27', '11:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(182, 'approved', '{}', '{X03250311,X04260306,X03250301,X03250307}', '{}', pg_temp.wib('2026-06-27', '11:00'), pg_temp.wib('2026-07-08', '14:00'));

-- 183: Program Studi Informatika
select pg_temp.keg(183, 'Student Exchange Kecerdasan Buatan di National Taiwan University', 68, 2, 'outbound', '2026-03-02', '2026-06-20', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,8}', pg_temp.wib('2026-06-28', '13:45'), 'revision_requested', pg_temp.wib('2026-07-04', '13:30'), '{ia,ir}', 'Dua NRP tidak sesuai surat tugas; mohon perbarui data peserta.', '[]'::jsonb);
select pg_temp.peserta(183, 'revision_requested', '{B11247302,B11258007,B11257605,B11236858}', '{}', '{PG591795}', pg_temp.wib('2026-06-28', '13:45'), pg_temp.wib('2026-07-04', '13:30'));

-- 184: Program Studi Akuntansi
select pg_temp.keg(184, 'Credit Transfer Akuntansi Forensik di Yonsei University', 6, 33, 'outbound', '2026-03-16', '2026-06-27', 'offline', 'Yonsei University', 'KR', 31, '{4,16,17}', pg_temp.wib('2026-07-01', '10:45'), 'approved', pg_temp.wib('2026-07-19', '11:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(184, 'approved', '{D32247773,D32257260,D32236037,D32228656}', '{}', '{}', pg_temp.wib('2026-07-01', '10:45'), pg_temp.wib('2026-07-19', '11:30'));

-- 185: Program Studi Magister Arsitektur
select pg_temp.keg(185, 'Publikasi Bersama Desain Kota Pesisir dengan Kyoto Sangyo', 53, 5, 'outbound', '2026-04-13', '2026-06-29', 'hybrid', 'Kyoto Sangyo University', 'JP', 11, '{11,17}', pg_temp.wib('2026-07-01', '12:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "researcher"}]'::jsonb);

-- 186: Program Studi Magister Manajemen
select pg_temp.keg(186, 'Pengabdian Masyarakat Manajemen Rantai Pasok bersama Astra', 48, 40, 'outbound', '2026-06-22', '2026-06-27', 'hybrid', 'Kelurahan Kenjeran', 'ID', 12, '{4,12,17}', pg_temp.wib('2026-07-02', '16:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 187: Program Studi Teknik Sipil
select pg_temp.keg(187, 'Credit Transfer Manajemen Konstruksi di National Taiwan University', 55, 33, 'outbound', '2026-02-23', '2026-06-22', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,6,9,17}', pg_temp.wib('2026-07-03', '08:30'), 'approved', pg_temp.wib('2026-07-15', '10:30'), '{ia,ir}', null, '[{"full_name": "Prof. Chen Yu-Ting", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(187, 'approved', '{A11246886,A11236394}', '{}', '{}', pg_temp.wib('2026-07-03', '08:30'), pg_temp.wib('2026-07-15', '10:30'));

-- 188: Program Studi Pendidikan Guru Sekolah Dasar
select pg_temp.keg(188, 'Immersion Program Literasi Dasar di National University of Singapore', 73, 22, 'outbound', '2026-06-15', '2026-06-26', 'offline', 'National University of Singapore', 'SG', 19, '{4,5}', pg_temp.wib('2026-07-07', '09:00'), 'approved', pg_temp.wib('2026-07-10', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(188, 'approved', '{F51247118,F51247545,F51258597,F51246124,F51257495,F51236440,F51247336,F51238236,F51256322}', '{}', '{PG616224,PG655830}', pg_temp.wib('2026-07-07', '09:00'), pg_temp.wib('2026-07-10', '13:00'));

-- 189: Program Studi Teknik Elektro
select pg_temp.keg(189, 'Magang Industri Teknik Elektro di PT Astra International Tbk', 65, 21, 'outbound', '2026-06-01', '2026-06-30', 'offline', 'PT Astra International Tbk', 'ID', 23, '{9,17}', pg_temp.wib('2026-07-09', '14:30'), 'approved', pg_temp.wib('2026-07-16', '16:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(189, 'approved', '{B12237202,B12236482,B12247079,B12248934,B12247442}', '{}', '{PG616609,PG578721}', pg_temp.wib('2026-07-09', '14:30'), pg_temp.wib('2026-07-16', '16:00'));

-- 190: Program Studi Kedokteran
select pg_temp.keg(190, 'Kuliah Tamu Kesehatan Gigi Komunitas dari National University of Singapore', 76, 15, 'inbound', '2026-05-22', '2026-05-22', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 19, '{4,6}', pg_temp.wib('2026-07-10', '09:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 191: Program Studi Informatika
select pg_temp.keg(191, 'Seminar Internasional Komputasi Awan bersama NTU', 68, 10, 'inbound', '2026-06-30', '2026-06-30', 'hybrid', 'Kampus PCU Siwalankerto', 'ID', 15, '{4,8,9}', pg_temp.wib('2026-07-13', '10:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Chen Yu-Ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]'::jsonb);

-- 192: Program Studi Magister Manajemen
select pg_temp.keg(192, 'Kuliah Tamu Pemasaran Berkelanjutan dari Yonsei University', 48, 15, 'inbound', '2026-06-26', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,9,12,17}', pg_temp.wib('2026-07-14', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}]'::jsonb);

-- 193: Program Studi Manajemen
select pg_temp.keg(193, 'Seminar Internasional Manajemen Rantai Pasok bersama Astra', 5, 10, 'inbound', '2026-07-06', '2026-07-07', 'offline', 'Gedung P PCU', 'ID', 12, '{4,8,12}', pg_temp.wib('2026-07-15', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dewi Anggraini, S.T., M.B.A.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 194: Program Studi Manajemen
select pg_temp.keg(194, 'Cultural Exchange (Inbound) Chulalongkorn – Kewirausahaan Digital', 5, 29, 'inbound', '2026-05-18', '2026-05-25', 'offline', 'Gedung Q PCU', 'ID', 25, '{4,9,17}', pg_temp.wib('2026-07-19', '10:00'), 'approved', pg_temp.wib('2026-07-25', '16:30'), '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(194, 'approved', '{}', '{X03250347,X04260348,X03250343}', '{PG643269,PG661938}', pg_temp.wib('2026-07-19', '10:00'), pg_temp.wib('2026-07-25', '16:30'));

-- 195: Program Studi Desain Interior
select pg_temp.keg(195, 'Staff Exchange Dosen Desain Interior ke PT Unilever Indonesia Tbk', 59, 3, 'outbound', '2026-06-01', '2026-06-13', 'hybrid', 'PT Unilever Indonesia Tbk', 'ID', 21, '{4,12}', pg_temp.wib('2026-07-24', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 196: Program Studi Kedokteran
select pg_temp.keg(196, 'Credit Transfer Kesehatan Masyarakat di University of Amsterdam', 76, 33, 'outbound', '2026-03-30', '2026-07-19', 'offline', 'University of Amsterdam, Amsterdam', 'NL', 17, '{6}', pg_temp.wib('2026-07-25', '15:30'), 'approved', pg_temp.wib('2026-08-03', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(196, 'approved', '{G61246171,G61236074}', '{}', '{PG505398,PG615813}', pg_temp.wib('2026-07-25', '15:30'), pg_temp.wib('2026-08-03', '10:00'));

-- 197: Program Studi Desain Komunikasi Visual
select pg_temp.keg(197, 'MBKM Pertukaran Mahasiswa Desain Komunikasi Visual di PT Unilever Indonesia Tbk', 63, 38, 'outbound', '2026-03-02', '2026-06-15', 'offline', 'PT Unilever Indonesia Tbk', 'ID', 21, '{4,11,12}', pg_temp.wib('2026-08-06', '12:45'), 'approved', pg_temp.wib('2026-08-15', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(197, 'approved', '{C21236671,C21247016,C21236260}', '{}', '{PG526649,PG657693}', pg_temp.wib('2026-08-06', '12:45'), pg_temp.wib('2026-08-15', '10:00'));

-- 198: Program Studi Teknik Mesin
select pg_temp.keg(198, 'Magang Internasional Teknik Mesin di National Taiwan University', 69, 21, 'outbound', '2026-06-01', '2026-07-02', 'offline', 'National Taiwan University', 'TW', 30, '{7,12,17}', pg_temp.wib('2026-08-24', '10:00'), 'approved', pg_temp.wib('2026-09-12', '14:00'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(198, 'approved', '{B14258346,B14248258}', '{}', '{PG549679}', pg_temp.wib('2026-08-24', '10:00'), pg_temp.wib('2026-09-12', '14:00'));

-- 199: Program Studi Ilmu Komunikasi
select pg_temp.keg(199, 'Credit Transfer Komunikasi Krisis di Yonsei University', 57, 33, 'outbound', '2026-03-09', '2026-06-17', 'offline', 'Yonsei University, Seoul', 'KR', 31, '{4,16}', pg_temp.wib('2026-08-25', '10:00'), 'approved', pg_temp.wib('2026-09-12', '14:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(199, 'approved', '{E42226484,E42248653,E42236808,E42227216}', '{}', '{PG501042}', pg_temp.wib('2026-08-25', '10:00'), pg_temp.wib('2026-09-12', '14:00'));

-- 200: Program Studi Arsitektur
select pg_temp.keg(200, 'Double Degree Arsitektur Tropis di University of Amsterdam', 54, 17, 'outbound', '2026-02-02', '2026-07-21', 'offline', 'University of Amsterdam', 'NL', 32, '{11}', pg_temp.wib('2026-08-28', '10:00'), 'approved', pg_temp.wib('2026-09-10', '14:00'), '{ia,ir}', null, '[{"full_name": "Dr. Anouk Smit", "institution": "University of Amsterdam", "country_code": "NL", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(200, 'approved', '{A12247634}', '{}', '{PG539055}', pg_temp.wib('2026-08-28', '10:00'), pg_temp.wib('2026-09-10', '14:00'));

-- >>> supabase/seed-supabase/07_kegiatan_2026_2027.sql
-- seed-supabase/07_kegiatan_2026_2027 (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- AY 2026/2027 up to 2026-10-03: kegiatan 201-220 (verified, waiting for Mobility incl. one duplicate-student decision, in revision, drafts).
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;

-- 201: Program Studi Informatika
select pg_temp.keg(201, 'Cultural Exchange (Inbound) NTU – Kecerdasan Buatan', 68, 29, 'inbound', '2026-08-03', '2026-08-08', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4}', pg_temp.wib('2026-08-18', '12:00'), 'approved', pg_temp.wib('2026-08-20', '14:30'), '{ia,ir}', null, '[{"full_name": "Dr. Huang Jun-Wei", "institution": "National Taiwan University", "country_code": "TW", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(201, 'approved', '{}', '{X04260320,X03250313,X04260316}', '{PG593383,PG591795}', pg_temp.wib('2026-08-18', '12:00'), pg_temp.wib('2026-08-20', '14:30'));

-- 202: Program Studi Manajemen
select pg_temp.keg(202, 'Immersion Program Manajemen Rantai Pasok di Yonsei University', 5, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University', 'KR', 31, '{4,8,9}', pg_temp.wib('2026-08-24', '10:00'), 'approved', pg_temp.wib('2026-08-28', '12:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(202, 'approved', '{D31236101,D31256312,D31258008,D31227742,D31248399,D31258883,D31248402,D31247059,D31256420,D31228283,D31237873,D31248761,D31237541,D31236401}', '{}', '{PG643269}', pg_temp.wib('2026-08-24', '10:00'), pg_temp.wib('2026-08-28', '12:00'));

-- 203: Program Studi Teknik Sipil
select pg_temp.keg(203, 'Studi Ekskursi Teknik Sipil ke Chulalongkorn University, Bangkok', 55, 24, 'outbound', '2026-08-10', '2026-08-14', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 25, '{4,6,11}', pg_temp.wib('2026-08-24', '12:00'), 'pending', pg_temp.wib('2026-08-24', '12:00'), '{ia,ir}', null, '[{"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(203, 'pending', '{A11246886,A11247207,A11256435,A11248814,A11258276,A11238958,A11238408,A11236661,A11226056,A11227441,A11236394,A11246063}', '{}', '{PG648486,PG564161}', pg_temp.wib('2026-08-24', '12:00'), null);

-- 204: Program Studi Magister Manajemen
select pg_temp.keg(204, 'Immersion Program Manajemen Rantai Pasok (Magister Manajemen)', 48, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University', 'KR', 31, '{4,17}', pg_temp.wib('2026-08-27', '10:00'), 'pending', pg_temp.wib('2026-08-27', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(204, 'pending', '{D31236101,D31256312,H71258825}', '{}', '{}', pg_temp.wib('2026-08-27', '10:00'), null);
select realisasi._scan_conflicts(pg_temp.aid(204)) where not exists (select 1 from realisasi.participant_conflicts where pg_temp.aid(204) in (activity_a, activity_b));

-- 205: Program Studi Kedokteran
select pg_temp.keg(205, 'Short Program Pendidikan Klinis di Kyoto Sangyo University', 76, 23, 'outbound', '2026-08-10', '2026-08-23', 'offline', 'Kyoto Sangyo University, Kyoto', 'JP', 11, '{4,6,17}', pg_temp.wib('2026-08-29', '10:00'), 'pending', pg_temp.wib('2026-08-29', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(205, 'pending', '{G61257371,G61248311,G61258355,G61246171,G61237319,G61226627,G61246376,G61228465,G61246402,G61236074}', '{}', '{PG615813}', pg_temp.wib('2026-08-29', '10:00'), null);

-- 206: Program Studi Akuntansi
select pg_temp.keg(206, 'Immersion Program Akuntansi Forensik di Yonsei University', 6, 22, 'outbound', '2026-08-17', '2026-08-27', 'offline', 'Yonsei University', 'KR', 31, '{8,16}', pg_temp.wib('2026-08-29', '15:00'), 'approved', pg_temp.wib('2026-09-01', '14:30'), '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(206, 'approved', '{D32247516,D32227188,D32228238,D32237065,D32248238,D32247773,D32227795,D32258446,D32237743}', '{}', '{PG641614}', pg_temp.wib('2026-08-29', '15:00'), pg_temp.wib('2026-09-01', '14:30'));

-- 207: Program Studi Sastra Inggris
select pg_temp.keg(207, 'Staff Exchange Dosen Sastra Inggris ke Kyoto Sangyo University', 61, 3, 'outbound', '2026-08-17', '2026-08-24', 'hybrid', 'Kyoto Sangyo University', 'JP', 11, '{4,10}', pg_temp.wib('2026-08-30', '08:00'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}]'::jsonb);

-- 208: Program Studi Teknik Sipil
select pg_temp.keg(208, 'Seminar Internasional Rekayasa Gempa bersama Chulalongkorn', 55, 10, 'inbound', '2026-08-19', '2026-08-20', 'hybrid', 'Gedung T PCU', 'ID', 25, '{4,9,11}', pg_temp.wib('2026-08-30', '12:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]'::jsonb);

-- 209: Program Studi Magister Teknik Sipil
select pg_temp.keg(209, 'Staff Exchange Dosen Magister Teknik Sipil ke Yonsei University', 56, 3, 'outbound', '2026-08-24', '2026-08-30', 'hybrid', 'Yonsei University', 'KR', 31, '{4,9,11}', pg_temp.wib('2026-09-09', '09:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Kim Soo-yeon", "institution": "Yonsei University", "country_code": "KR", "role": "staff_visitor"}]'::jsonb);

-- 210: Program Studi Manajemen
select pg_temp.keg(210, 'Immersion Program Manajemen Rantai Pasok di National Taiwan University', 5, 22, 'outbound', '2026-09-07', '2026-09-14', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{8,12}', pg_temp.wib('2026-09-16', '11:00'), 'approved', pg_temp.wib('2026-09-20', '11:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(210, 'approved', '{D31248101,D31258938,D31258008,D31236401,D31236200,D31237873,D31227742,D31236101,D31248761,D31237541,D31228357}', '{}', '{PG643269}', pg_temp.wib('2026-09-16', '11:00'), pg_temp.wib('2026-09-20', '11:00'));

-- 211: Program Studi Manajemen
select pg_temp.keg(211, 'Pengabdian Masyarakat Kewirausahaan Digital bersama Astra', 5, 40, 'outbound', '2026-09-13', '2026-09-15', 'offline', 'Kelurahan Kenjeran', 'ID', 12, '{4,9,12}', pg_temp.wib('2026-09-20', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 212: Program Studi Akuntansi
select pg_temp.keg(212, 'Short Program (Inbound) Chulalongkorn – Perpajakan Internasional', 6, 23, 'inbound', '2026-09-07', '2026-09-20', 'offline', 'Gedung Q PCU', 'ID', 29, '{4,8,17}', pg_temp.wib('2026-09-23', '13:00'), 'pending', pg_temp.wib('2026-09-23', '13:00'), '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(212, 'pending', '{}', '{X04260344,X04260350,X04260348,X03250343,X03250347,X03250345}', '{PG641614,PG508242}', pg_temp.wib('2026-09-23', '13:00'), null);

-- 213: Program Studi Informatika
select pg_temp.keg(213, 'Immersion Program Rekayasa Perangkat Lunak di National University of Singapore', 68, 22, 'outbound', '2026-09-07', '2026-09-18', 'offline', 'National University of Singapore', 'SG', 36, '{4,9,17}', pg_temp.wib('2026-09-23', '14:00'), 'pending', pg_temp.wib('2026-09-23', '14:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(213, 'pending', '{B11258208,B11248139,B11237976,B11246879,B11238934,B11247499}', '{}', '{PG593383}', pg_temp.wib('2026-09-23', '14:00'), null);

-- 214: Program Studi Desain Komunikasi Visual
select pg_temp.keg(214, 'Magang Internasional Desain Komunikasi Visual di Kyoto Sangyo University', 63, 21, 'outbound', '2026-08-03', '2026-09-18', 'offline', 'Kyoto Sangyo University', 'JP', 27, '{4,9,11}', pg_temp.wib('2026-09-26', '09:00'), 'revision_requested', pg_temp.wib('2026-09-27', '09:00'), '{ia,ir}', 'Mohon lengkapi daftar dosen pendamping sesuai surat tugas.', '[]'::jsonb);
select pg_temp.peserta(214, 'revision_requested', '{C21236260,C21226359}', '{}', '{PG526649,PG657693}', pg_temp.wib('2026-09-26', '09:00'), pg_temp.wib('2026-09-27', '09:00'));

-- 215: Program Studi Desain Interior
select pg_temp.keg(215, 'Magang Internasional Desain Interior di Chulalongkorn University', 59, 21, 'outbound', '2026-08-03', '2026-09-22', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,11,12}', pg_temp.wib('2026-09-26', '12:00'), 'approved', pg_temp.wib('2026-09-30', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(215, 'approved', '{C22236769,C22227224,C22257085}', '{}', '{}', pg_temp.wib('2026-09-26', '12:00'), pg_temp.wib('2026-09-30', '10:00'));

-- 216: Program Studi Manajemen
select pg_temp.keg(216, 'Magang Industri Manajemen di Universitas Gadjah Mada', 5, 21, 'outbound', '2026-08-03', '2026-09-29', 'offline', 'Universitas Gadjah Mada', 'ID', 28, '{9,17}', pg_temp.wib('2026-10-02', '10:00'), 'revision_requested', pg_temp.wib('2026-10-02', '11:00'), '{ia,ir}', 'Dua NRP tidak sesuai surat tugas; mohon perbarui data peserta.', '[]'::jsonb);
select pg_temp.peserta(216, 'revision_requested', '{D31248545,D31246583,D31247028,D31228515,D31236499}', '{}', '{PG643269,PG626211}', pg_temp.wib('2026-10-02', '10:00'), pg_temp.wib('2026-10-02', '11:00'));

-- 217: Program Studi Desain Komunikasi Visual
select pg_temp.keg(217, 'Kuliah Tamu Desain Berkelanjutan dari Ludwig Maximilian University of Munich', 63, 15, 'inbound', '2026-09-08', '2026-09-09', 'offline', 'Gedung Q PCU', 'ID', 42, '{4,11,17}', null, null, null, '{}', null, '[{"full_name": "Prof. Dr. Markus Klein", "institution": "Ludwig Maximilian University of Munich", "country_code": "DE", "role": "speaker"}]'::jsonb);

-- 218: Program Studi Manajemen
select pg_temp.keg(218, 'Studi Ekskursi Manajemen ke Chulalongkorn University', 5, 24, 'outbound', '2026-09-07', '2026-09-12', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8,12}', null, null, null, '{ia}', null, '[]'::jsonb);
select pg_temp.peserta(218, 'draft', '{D31227308,D31248011,D31258883,D31237888,D31248402,D31248243,D31256420,D31228283,D31247059,D31256312,D31237627,D31248399}', '{}', '{PG643269}', null, null);

-- 219: Program Studi Teknik Mesin
select pg_temp.keg(219, 'Short Program (Inbound) NUS – Manufaktur Aditif', 69, 23, 'inbound', '2026-09-14', '2026-09-23', 'offline', 'Gedung T PCU', 'ID', 36, '{7,12}', null, null, null, '{}', null, '[{"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(219, 'draft', '{}', '{X03250335,X04260332,X03250339,X04260338,X04260340,X04260334}', '{}', null, null);

-- 220: Program Studi Akuntansi
select pg_temp.keg(220, 'Publikasi Bersama Perpajakan Internasional dengan Yonsei', 6, 5, 'outbound', '2026-08-03', '2026-10-02', 'hybrid', 'Yonsei University', 'KR', 31, '{16,17}', null, null, null, '{ia}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "researcher"}, {"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "researcher"}]'::jsonb);

select setval('realisasi.activity_code_seq', greatest(300, (select last_value from realisasi.activity_code_seq)));

-- >>> supabase/seed-supabase/08_refreeze_2025_2026.sql
-- seed-supabase/08_refreeze_2025_2026 (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- Re-freezes the AY 2025/2026 snapshots once after the bulk import (R-58), as of their original freeze moments, so
-- Ganjil and Setahun include the imported kegiatan; the earlier snapshots stay as superseded. No-op on a fresh install
-- (90_freeze.sql freezes later) and when already done.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.

do $$
declare s realisasi.kpi_snapshots; v_reason text := 'Bekukan ulang setelah impor data kegiatan 2025/2026';
begin
  for s in select * from realisasi.kpi_snapshots
            where academic_year_id = 1 and superseded_by is null and refreeze_reason is distinct from v_reason
              and exists (select 1 from realisasi.activities a where a.id = ('b5000000-0000-4000-8000-' || lpad('101', 12, '0'))::uuid)
            order by frozen_at
  loop
    perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at, (select id from kerjasama.profiles where akun_id = 1),
                              v_reason, s.id);
  end loop;
end $$;

-- >>> supabase/seed-supabase/09_registries_tambahan.sql
-- seed-supabase/09_registries_tambahan (simks-partnership): mock BAAK students for the additional bulk kegiatan
-- (10_kegiatan_tambahan_1..8 = kegiatan 221-420). Each 10_kegiatan_tambahan_N file owns one disjoint slice (marked
-- below), so the new kegiatan never share a student with each other or with the 06/07 kegiatan (no new conflicts).
-- NRPs use sequence digit 9 ({prefix}{intake}9{nnn}); inbound X05/X06. Prodi/faculty names follow 05_registries_bulk.
-- Self-contained and idempotent (existing rows are skipped). Writes only mock_baak; SIM Kerjasama tables are only read.
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values
  -- 10_kegiatan_tambahan_1
  ('B11239558', 'Fiona Chandra', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11239097', 'Samuel Hadinata', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11229093', 'Bryan Suryadi', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11239548', 'Fiona Rusli', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11249656', 'Kevin Prawira', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11259876', 'Joshua Hartanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11229911', 'Carissa Wibisono', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11249376', 'Felix Lim', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11239054', 'Michelle Kartika', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11239992', 'Evan Lim', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11249731', 'Michelle Hadinata', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11259793', 'Nicholas Hartanto', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11229772', 'Aurelia Susilo', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11249484', 'Tiffany Tanuwijaya', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B13249805', 'Sharon Tan', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13239251', 'Evan Halim', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13249021', 'Valencia Santoso', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13249069', 'Alvin Soetomo', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13259437', 'Owen Halim', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('B13259187', 'Stefanie Pangestu', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2025, 'active'),
  ('B13249780', 'Ricky Halim', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13239748', 'Adrian Widjaja', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13249311', 'Glory Prawira', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2024, 'active'),
  ('B13239273', 'Aurelia Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('B13239019', 'Agnes Pangestu', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 'regular', null, null, 2023, 'active'),
  ('X06269001', 'Yu-ting Hsieh', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X06259002', 'Darren Lim Jun Wei', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2025, 'active'),
  ('X06259003', 'Zhang Wei', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Xiamen University', 'CN', 2025, 'active'),
  ('X05259004', 'Leon Wagner', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Technische Hochschule Deggendorf', 'DE', 2025, 'active'),
  ('X05269005', 'Nicole Ong Hui Min', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Temasek Polytechnic', 'SG', 2026, 'active'),
  -- 10_kegiatan_tambahan_2
  ('B12239256', 'Ignatius Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12259675', 'Irvan Effendi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12259921', 'Hendrik Suryadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12249585', 'Yemima Effendi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12229628', 'Bryan Jayadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2022, 'active'),
  ('B12259849', 'Kristina Tanuwijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12239294', 'Glory Effendi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12239153', 'Samuel Prawira', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12249412', 'Valencia Budiman', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12259553', 'Raymond Wijaya', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12259448', 'Irvan Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12239792', 'Angela Pangestu', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12249256', 'Elisabeth Kusnadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12249376', 'Nicholas Sutanto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12239075', 'Elisabeth Hadinata', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B14239757', 'Calvin Tedja', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14229309', 'Kenneth Kartika', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2022, 'active'),
  ('B14239830', 'Lukas Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2023, 'active'),
  ('B14229407', 'Kristina Rusli', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2022, 'active'),
  ('B14259358', 'Samuel Kusnadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14229541', 'Agnes Santoso', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2022, 'active'),
  ('B14249427', 'Joanne Halim', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2024, 'active'),
  ('B14249899', 'Hendrik Budiman', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2024, 'active'),
  ('B14259010', 'Natasha Halim', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2025, 'active'),
  ('B14229977', 'Jessica Budiman', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 'regular', null, null, 2022, 'active'),
  ('X06269006', 'Hannah Schulz', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Technische Hochschule Deggendorf', 'DE', 2026, 'active'),
  ('X05269007', 'Chloe Mitchell', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Melbourne', 'AU', 2026, 'active'),
  ('X05269008', 'Min-seo Yoon', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X06269009', 'Yuto Ishikawa', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kanazawa Institute of Technology', 'JP', 2026, 'active'),
  ('X06269010', 'Aisyah binti Hamzah', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universiti Teknologi Malaysia', 'MY', 2026, 'active'),
  -- 10_kegiatan_tambahan_3
  ('D32249150', 'Steven Rusli', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32259472', 'Kevin Rusli', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32249331', 'Fransiska Wijaya', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32229204', 'Adrian Prawira', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32239758', 'Amanda Hartanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32249505', 'Felix Chandra', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32259900', 'Wendy Budiman', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32229279', 'Fiona Wibisono', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32249196', 'Clara Sutanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32259976', 'Darren Gunawan', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D32249493', 'Karina Prawira', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32229661', 'Samuel Budiman', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('D32239572', 'Felix Hartanto', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32239508', 'Samuel Rusli', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32259984', 'Karina Wijaya', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('D31249692', 'Gilbert Wijaya', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31239726', 'Ricky Chandra', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31229821', 'Yemima Hartanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31229027', 'Irvan Budiman', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31229451', 'Alvin Kartika', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31239549', 'Nicholas Angkasa', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249207', 'Raymond Kartika', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31259757', 'Bryan Hadinata', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31249746', 'Bella Tanuwijaya', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31239185', 'Joanne Santoso', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('X06269011', 'Lachlan Reid', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Monash University', 'AU', 2026, 'active'),
  ('X06269012', 'Lim Wei Jie', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Taylor''s University', 'MY', 2026, 'active'),
  ('X05259013', 'Nur Hazwani binti Yusof', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universiti Brunei Darussalam', 'BN', 2025, 'active'),
  ('X05259014', 'Zoe Campbell', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Curtin University', 'AU', 2025, 'active'),
  ('X06259015', 'Ji-woo Shin', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2025, 'active'),
  -- 10_kegiatan_tambahan_4
  ('D31259442', 'Michelle Angkasa', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31239083', 'Joanne Chandra', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31229852', 'Gilbert Angkasa', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31239791', 'Kenneth Sutanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249994', 'Kenneth Pangestu', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31239881', 'Evan Pangestu', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31229748', 'Calvin Kartika', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31239043', 'Priscilla Kartika', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31239676', 'Joshua Jayadi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249546', 'Joanne Tan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31249493', 'Kevin Lukito', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31249971', 'Joanne Tedja', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31249923', 'Joshua Susilo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31249797', 'Matthew Rusli', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31239469', 'Vincent Soetomo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31229309', 'Raymond Jayadi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31259588', 'Ricky Kusnadi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2025, 'active'),
  ('D31249029', 'Albert Kusnadi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31239820', 'Karina Rusli', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249725', 'Samuel Lukito', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71249141', 'Aurelia Hadinata', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71249876', 'Hana Halim', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71249078', 'Ricky Pangestu', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2024, 'active'),
  ('H71259136', 'Carissa Budiman', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('H71259686', 'Felix Soetomo', 'H', 'School of Business and Management', 'Magister Manajemen', 'regular', null, null, 2025, 'active'),
  ('X05259016', 'Thanakorn Chaiwat', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2025, 'active'),
  ('X06259017', 'Chen-wei Lo', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2025, 'active'),
  ('X05269018', 'Wong Ka Yan', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hong Kong Baptist University', 'HK', 2026, 'active'),
  ('X05259019', 'Ananya Sharma', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Manipal Academy of Higher Education', 'IN', 2025, 'active'),
  ('X05259020', 'Thijs van Dijk', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2025, 'active'),
  -- 10_kegiatan_tambahan_5
  ('C22259857', 'Fiona Darmawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2025, 'active'),
  ('C22229994', 'Irvan Darmawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22239024', 'Nathania Lim', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22249123', 'Debora Hartanto', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22249999', 'Raymond Effendi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22229438', 'Yemima Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('C22239955', 'Kristina Santoso', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22239188', 'Marcel Chandra', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22249635', 'Valencia Halim', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22249514', 'Sharon Chandra', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22239208', 'Carissa Tan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22249824', 'Yemima Tan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22239295', 'Joanne Wibisono', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2023, 'active'),
  ('C22249177', 'Joshua Soetomo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2024, 'active'),
  ('C22229221', 'Gerald Kartika', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Interior', 'regular', null, null, 2022, 'active'),
  ('E42259904', 'Albert Pangestu', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2025, 'active'),
  ('E42249976', 'Kenneth Sanjaya', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E42239200', 'Darren Wijaya', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42249697', 'Kenneth Prawira', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E42239001', 'Valencia Hadinata', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42239798', 'Darren Pangestu', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42249420', 'Felix Effendi', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('E42239215', 'Steven Suryadi', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42239743', 'Glory Rusli', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2023, 'active'),
  ('E42249210', 'Matthew Kartika', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 'regular', null, null, 2024, 'active'),
  ('X06259021', 'Paul Richter', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hochschule Bremen', 'DE', 2025, 'active'),
  ('X05259022', 'Ruby Anderson', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Technology Sydney', 'AU', 2025, 'active'),
  ('X05259023', 'Rin Matsumoto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kanazawa Institute of Technology', 'JP', 2025, 'active'),
  ('X06259024', 'Muhammad Haziq bin Ali', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universiti Brunei Darussalam', 'BN', 2025, 'active'),
  ('X05259025', 'Marcus Goh', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Temasek Polytechnic', 'SG', 2025, 'active'),
  -- 10_kegiatan_tambahan_6
  ('C21239954', 'Hana Gunawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239549', 'Cynthia Tanuwijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21259848', 'Calvin Jayadi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21259343', 'Ricky Tedja', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21239991', 'Clara Effendi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239626', 'Edward Tan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239301', 'Matthew Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21249196', 'Kenneth Widjaja', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21249481', 'Irvan Angkasa', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21249147', 'Joanne Darmawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21259948', 'Tiffany Suryadi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21259543', 'Joshua Santoso', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21239888', 'Valencia Gunawan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239659', 'Kevin Wibisono', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21249776', 'Vincent Setiadi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21229377', 'Alvin Tan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21259428', 'Gerald Angkasa', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21259142', 'Felix Santoso', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21229391', 'Felix Widjaja', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21239562', 'Natasha Jayadi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21249999', 'Raymond Wibisono', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21229931', 'Jovan Tanuwijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21249451', 'Steven Prawira', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21239724', 'Debora Susilo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239896', 'Darren Rusli', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('X06269026', 'Hamish Clarke', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Technology Sydney', 'AU', 2026, 'active'),
  ('X06269027', 'Mia Robertson', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Technology Sydney', 'AU', 2026, 'active'),
  ('X05259028', 'Lena Koch', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hochschule Bremen', 'DE', 2025, 'active'),
  ('X05259029', 'Abigail Vander Meer', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Calvin University', 'US', 2025, 'active'),
  ('X06269030', 'Nurul Izzah binti Rahim', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Taylor''s University', 'MY', 2026, 'active'),
  -- 10_kegiatan_tambahan_7
  ('B11229965', 'Nathania Kartika', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11239432', 'Owen Chandra', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11229081', 'Elisabeth Wijaya', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11259395', 'Owen Widjaja', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2025, 'active'),
  ('B11249182', 'Clara Setiadi', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B12239310', 'Vincent Lukito', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12249808', 'Yoel Lim', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2024, 'active'),
  ('B12259428', 'Felix Kartika', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12239803', 'Bella Widjaja', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12239093', 'Owen Kusnadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('D31239877', 'Darren Kartika', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31239764', 'Nathania Tan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249852', 'Yoel Rusli', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D31229441', 'Steven Sanjaya', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31249140', 'Gilbert Sutanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D32239280', 'Darren Kusnadi', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32239903', 'Christian Rusli', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32249932', 'Karina Santoso', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32249413', 'Sharon Budiman', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32259676', 'Bryan Kusnadi', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2025, 'active'),
  ('C21229456', 'Agnes Soetomo', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21239107', 'Marcel Sanjaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21249850', 'Wendy Lukito', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('C21229874', 'Edward Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21239176', 'Samuel Tan', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('X06269031', 'Hui-min Tseng', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National Taiwan University', 'TW', 2026, 'active'),
  ('X05269032', 'Siriporn Kaewmanee', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Chulalongkorn University', 'TH', 2026, 'active'),
  ('X06259033', 'Oscar Bennett', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Monash University', 'AU', 2025, 'active'),
  ('X05269034', 'Sota Fujimoto', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Kanazawa Institute of Technology', 'JP', 2026, 'active'),
  ('X05269035', 'Maximilian Braun', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Hochschule Bremen', 'DE', 2026, 'active'),
  -- 10_kegiatan_tambahan_8
  ('B11239024', 'Karina Kartika', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11239809', 'Jessica Angkasa', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2023, 'active'),
  ('B11249208', 'Kristina Budiman', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2024, 'active'),
  ('B11229632', 'Adrian Darmawan', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B11229075', 'Nicholas Chandra', 'B', 'Fakultas Teknologi Industri', 'Informatika', 'regular', null, null, 2022, 'active'),
  ('B12259442', 'Kevin Suryadi', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2025, 'active'),
  ('B12239276', 'Vincent Prawira', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12239596', 'Alvin Hartanto', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12239147', 'Irvan Susilo', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('B12239970', 'Priscilla Santoso', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 'regular', null, null, 2023, 'active'),
  ('D31229599', 'Owen Gunawan', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2022, 'active'),
  ('D31239924', 'Kenneth Kusnadi', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31239267', 'Adrian Susilo', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31239013', 'Valencia Wijaya', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2023, 'active'),
  ('D31249008', 'Priscilla Hartanto', 'D', 'School of Business and Management', 'Manajemen', 'regular', null, null, 2024, 'active'),
  ('D32239187', 'Christian Soetomo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32249796', 'Valencia Sanjaya', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32239589', 'Gerald Effendi', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2023, 'active'),
  ('D32249171', 'Joshua Hadinata', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2024, 'active'),
  ('D32229270', 'Amanda Soetomo', 'D', 'School of Business and Management', 'Akuntansi', 'regular', null, null, 2022, 'active'),
  ('C21229761', 'Tiffany Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2022, 'active'),
  ('C21259377', 'Stefanie Widjaja', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2025, 'active'),
  ('C21239657', 'Karina Jayadi', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21239466', 'Fiona Wijaya', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2023, 'active'),
  ('C21249938', 'Angela Tedja', 'C', 'Fakultas Humaniora dan Industri Kreatif', 'Desain Komunikasi Visual', 'regular', null, null, 2024, 'active'),
  ('X06269036', 'Sarah Teo Xin Yi', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'National University of Singapore', 'SG', 2026, 'active'),
  ('X05269037', 'Seung-hyun Baek', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Yonsei University', 'KR', 2026, 'active'),
  ('X06269038', 'Tan Mei Ling', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Taylor''s University', 'MY', 2026, 'active'),
  ('X06269039', 'Arif bin Zulkifli', 'B', 'Fakultas Teknologi Industri', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'Universiti Teknologi Malaysia', 'MY', 2026, 'active'),
  ('X06269040', 'Fleur de Jong', 'D', 'School of Business and Management', 'Program Pertukaran (Inbound)', 'inbound_exchange', 'University of Amsterdam', 'NL', 2026, 'active')
on conflict (nrp) do nothing;

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_1.sql
-- seed-supabase/10_kegiatan_tambahan_1 (simks-partnership): additional bulk kegiatan 221-245, adapted from the local
-- demo seed supabase/seed/04_bulk_1.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 11, 19, 25, 30, 34, 83, 105, 107, 126, 181, 184, 188, 191, 193, 200. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{11,19,25,30,34,83,105,107,126,181,184,188,191,193,200}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_1: SIM Kerjasama agreements missing, kegiatan 221-245 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(221, 'Kuliah Tamu Machine Learning untuk Visi Komputer dari Kanazawa Institute of Technology', 68, 15, 'inbound', '2025-09-15', '2025-09-16', 'offline', 'Auditorium Gedung P PCU', 'ID', 105, '{4,9}', 'Kuliah tamu dua hari tentang deep learning untuk inspeksi visual di industri manufaktur Jepang, disertai sesi praktik klasifikasi citra cacat produk bagi mahasiswa Informatika semester 5.', pg_temp.wib('2025-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Hiroshi Tanaka", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(222, 'Inbound Student Exchange Informatika Xiamen University Semester Ganjil 2025', 68, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 184, '{4,17}', 'Mahasiswa Xiamen University mengikuti satu semester perkuliahan Informatika di PCU (Pemrograman Web, Basis Data Lanjut, Kecerdasan Buatan) dengan pengakuan kredit di universitas asal.', pg_temp.wib('2026-01-08', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'));
select pg_temp.bulk_pset(222, '{}', '{X06259003}', '{PG557816}');
select pg_temp.bulk_act(223, 'Riset Bersama Sensor IoT untuk Pertanian Presisi dengan Universitas Brawijaya', 65, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline', 'Kebun Percobaan Fakultas Pertanian Universitas Brawijaya, Malang', 'ID', 193, '{2,9}', 'Tim dosen Teknik Elektro melakukan kalibrasi bersama jaringan sensor kelembapan tanah berbasis LoRaWAN di kebun percobaan Universitas Brawijaya serta menyusun rencana publikasi hasil uji lapangan.', pg_temp.wib('2025-10-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Bambang Susilo, M.Sc.Agr.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(224, 'Short Program Data Science and Analytics di NTUST Taipei 2025', 68, 23, 'outbound', '2025-10-20', '2025-11-07', 'offline', 'NTUST Taipei Campus, Department of Computer Science and Information Engineering', 'TW', 200, '{4,9}', 'Program singkat tiga minggu berisi kuliah analitik big data, praktikum Python untuk machine learning, dan proyek kelompok analisis data transportasi publik kota Taipei.', pg_temp.wib('2025-11-20', '09:00'), 'approved', pg_temp.wib('2025-11-27', '14:00'));
select pg_temp.bulk_pset(224, '{B11239558,B11239097,B11229093,B11239548}', '{}', '{PG663266}');
select pg_temp.bulk_act(225, 'Workshop Penyelarasan Kurikulum Rekayasa Perangkat Lunak bersama ITB', 68, 11, 'outbound', '2025-11-17', '2025-11-18', 'offline', 'Kampus ITB Ganesha, Bandung', 'ID', 83, '{4}', 'Lokakarya penyelarasan capaian pembelajaran mata kuliah rekayasa perangkat lunak dan DevOps antara Informatika PCU dan STEI ITB, menghasilkan draf peta mata kuliah setara untuk program pertukaran.', pg_temp.wib('2025-11-28', '09:00'), null, null, p_co_units => '{28}');
select pg_temp.bulk_act(226, 'Inbound Short Program Industrial Automation TH Deggendorf 2025', 67, 23, 'inbound', '2025-11-24', '2025-12-12', 'offline', 'Laboratorium Sistem Manufaktur Gedung P PCU', 'ID', 126, '{4,9,17}', 'Mahasiswa Technische Hochschule Deggendorf mengikuti program tiga minggu tentang otomasi lini produksi dengan PLC dan sistem MES, termasuk kunjungan industri ke kawasan SIER Surabaya.', pg_temp.wib('2025-12-22', '09:00'), 'approved', pg_temp.wib('2026-01-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(226, '{}', '{X05259004}', '{PG681184}');
select pg_temp.bulk_act(227, 'Kuliah Bersama Cloud Computing dengan University of Amsterdam', 68, 34, 'inbound', '2025-09-08', '2025-12-12', 'online', 'Microsoft Teams', null, 191, '{4,9}', 'Mata kuliah Cloud Computing diajarkan bersama secara daring oleh dosen Informatika PCU dan dosen University of Amsterdam selama satu semester, mencakup arsitektur serverless dan kontainerisasi.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Pieter de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(228, 'Magang Smart Factory di Technische Hochschule Deggendorf', 67, 21, 'outbound', '2026-01-05', '2026-01-30', 'offline', 'Technologie Campus Cham, Technische Hochschule Deggendorf', 'DE', 126, '{8,9}', 'Mahasiswa Teknik Industri magang di laboratorium smart production TH Deggendorf, mengerjakan pemetaan aliran nilai dan integrasi sensor untuk lini perakitan cerdas skala pilot.', pg_temp.wib('2026-02-12', '09:00'), 'approved', pg_temp.wib('2026-02-20', '14:00'));
select pg_temp.bulk_pset(228, '{B13239251,B13239748}', '{}', '{PG634699}');
select pg_temp.bulk_act(229, 'Seminar Internasional AI for Smart Manufacturing bersama Kanazawa Institute of Technology', 67, 35, 'inbound', '2026-02-24', '2026-02-25', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 105, '{8,9}', 'Seminar internasional dua hari membahas penerapan kecerdasan buatan pada pemeliharaan prediktif dan kendali kualitas, dihadiri 180 peserta luring dan daring dari kampus serta industri Jawa Timur.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Kenji Yamamoto", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "speaker"}, {"full_name": "Dr. Ayumi Sato", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "speaker"}]', p_co_units => '{28,68,65}');
select pg_temp.bulk_act(230, 'Student Exchange Informatika di National Taiwan University Semester Genap 2026', 68, 2, 'outbound', '2026-02-16', '2026-06-19', 'offline', 'National Taiwan University, Main Campus Taipei', 'TW', 30, '{4,17}', 'Tiga mahasiswa Informatika menempuh satu semester di National Taiwan University dengan mata kuliah Deep Learning, Distributed Systems, dan Mandarin dasar; kredit diakui melalui skema transfer kredit.', pg_temp.wib('2026-07-02', '09:00'), 'approved', pg_temp.wib('2026-07-10', '14:00'));
select pg_temp.bulk_pset(230, '{B11249656,B11229911,B11239054}', '{}', '{}');
select pg_temp.bulk_act(231, 'Inbound Credit Transfer National Taiwan University di Prodi Informatika 2026', 68, 33, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengambil 18 SKS mata kuliah Informatika PCU (Pengembangan Aplikasi Mobile, Interaksi Manusia dan Komputer) yang dikonversi ke kredit di universitas asal.', pg_temp.wib('2026-06-24', '09:00'), 'approved', pg_temp.wib('2026-07-03', '14:00'));
select pg_temp.bulk_pset(231, '{}', '{X06269001}', '{PG593383}');
select pg_temp.bulk_act(232, 'Riset Bersama Digital Twin Lini Produksi dengan TH Deggendorf', 67, 4, 'inbound', '2026-03-09', '2026-05-29', 'hybrid', 'Laboratorium Sistem Produksi Gedung P PCU', 'ID', 126, '{9,12}', 'Pengembangan purwarupa digital twin lini perakitan skala laboratorium untuk simulasi penjadwalan dan pengurangan limbah produksi, dengan pertemuan daring mingguan dan kunjungan peneliti TH Deggendorf.', pg_temp.wib('2026-07-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr.-Ing. Markus Hofmann", "institution": "Technische Hochschule Deggendorf", "country_code": "DE", "role": "researcher"}]');
select pg_temp.bulk_act(233, 'Academic Exchange Teknik Industri National University of Singapore 2026', 67, 28, 'inbound', '2026-03-02', '2026-05-22', 'offline', 'Laboratorium Optimasi dan Rekayasa Industri Gedung P PCU', 'ID', 19, '{4,9}', 'Mahasiswa National University of Singapore mengikuti perkuliahan Riset Operasi dan Ergonomi Industri serta terlibat dalam proyek optimasi tata letak gudang mitra industri Teknik Industri PCU.', pg_temp.wib('2026-06-04', '09:00'), 'approved', pg_temp.wib('2026-06-12', '14:00'));
select pg_temp.bulk_pset(233, '{}', '{X06259002}', '{}');
select pg_temp.bulk_act(234, 'Pelatihan dan Sertifikasi IoT Developer bersama Temasek Polytechnic', 67, 44, 'inbound', '2026-04-20', '2026-04-24', 'offline', 'Laboratorium Internet of Things Gedung P PCU', 'ID', 188, '{4,8}', 'Pelatihan lima hari pemrograman mikrokontroler, protokol MQTT, dan dashboard IoT yang ditutup dengan ujian sertifikasi IoT Developer berstandar Temasek Polytechnic untuk 30 mahasiswa Teknik Industri dan Informatika.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Tan Jun Hao", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "visiting_lecturer"}]', p_co_units => '{68}');
select pg_temp.bulk_act(235, 'Kunjungan Akademik Teknik Industri ke Kyoto Sangyo University', 67, 27, 'outbound', '2026-04-13', '2026-04-16', 'offline', 'Kyoto Sangyo University, Kamigamo Campus', 'JP', 11, '{9,17}', 'Delegasi pimpinan Teknik Industri dan FTI meninjau laboratorium sistem informasi dan rekayasa produksi Kyoto Sangyo University untuk menindaklanjuti kerja sama serta merancang skema riset bersama periode 2026-2031.', pg_temp.wib('2026-04-27', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Takeshi Nakamura", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}]', p_co_units => '{28}');
select pg_temp.bulk_act(236, 'Pengabdian Masyarakat Smart Village Berbasis IoT bersama ITB', 68, 40, 'outbound', '2026-07-06', '2026-07-10', 'offline', 'Desa Ketapanrame, Trawas, Mojokerto', 'ID', 83, '{1,9,11}', 'Pemasangan sistem pemantauan debit air dan panel informasi desa berbasis IoT bersama tim ITB, disertai pelatihan perawatan perangkat bagi karang taruna desa.', pg_temp.wib('2026-07-20', '09:00'), null, null, p_co_units => '{28}');
select pg_temp.bulk_act(237, 'June Program Robotika dan Otomasi Industri di Temasek Polytechnic', 67, 23, 'outbound', '2026-06-22', '2026-07-10', 'offline', 'Temasek Polytechnic, Tampines Campus', 'SG', 188, '{4,9}', 'Program tiga minggu tentang pemrograman robot kolaboratif, machine vision, dan integrasi PLC di pusat otomasi Temasek Polytechnic, ditutup presentasi proyek otomasi lini perakitan.', pg_temp.wib('2026-07-22', '09:00'), 'approved', pg_temp.wib('2026-07-30', '14:00'));
select pg_temp.bulk_pset(237, '{B13249805,B13249021,B13249069,B13249311}', '{}', '{PG681184}');
select pg_temp.bulk_act(238, 'Inbound Short Program Lean Manufacturing Temasek Polytechnic 2026', 67, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline', 'Laboratorium Teknik Industri Gedung P PCU', 'ID', 188, '{4,9,17}', 'Mahasiswa Temasek Polytechnic mengikuti program empat minggu tentang lean manufacturing dan rantai pasok UMKM Jawa Timur, termasuk studi lapangan di dua pabrik mitra.', pg_temp.wib('2026-09-07', '09:00'), 'approved', pg_temp.wib('2026-09-15', '14:00'));
select pg_temp.bulk_pset(238, '{}', '{X05269005}', '{}');
select pg_temp.bulk_act(239, 'Guest Lecture Industry 4.0 Readiness dari Chulalongkorn University', 67, 7, 'inbound', '2026-08-19', '2026-08-19', 'online', 'Zoom Meeting', null, 25, '{8,9}', 'Kuliah tamu daring mengenai pengukuran kesiapan Industri 4.0 pada industri manufaktur Thailand dan pelajaran yang relevan bagi industri Indonesia, diikuti 150 mahasiswa Teknik Industri.', pg_temp.wib('2026-08-26', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Rattanakul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]');
select pg_temp.bulk_act(240, 'Studi Ekskursi Smart Manufacturing ke Kanazawa Institute of Technology', 67, 24, 'outbound', '2026-09-14', '2026-09-19', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,9}', 'Studi ekskursi enam hari ke laboratorium mekatronika Kanazawa Institute of Technology dan dua pabrik manufaktur di Hokuriku untuk mengamati penerapan sistem produksi cerdas dan otomasi.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'));
select pg_temp.bulk_pset(240, '{B13259437,B13259187,B13249780,B13239273,B13239019}', '{}', '{PG660389}');
select pg_temp.bulk_act(241, 'Magang AI Engineering di NTUST Artificial Intelligence Center', 68, 21, 'outbound', '2026-07-20', '2026-09-11', 'offline', 'NTUST Taipei Campus, Taiwan Building Technology Center', 'TW', 200, '{8,9}', 'Dua mahasiswa Informatika magang delapan minggu di pusat AI NTUST, mengembangkan pipeline pelabelan data dan model deteksi objek untuk inspeksi konstruksi.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'));
select pg_temp.bulk_pset(241, '{B11239992,B11229772}', '{}', '{}');
select pg_temp.bulk_act(242, 'Short Program Cyber-Physical Systems di Universiti Teknologi Malaysia', 68, 23, 'outbound', '2026-08-10', '2026-08-28', 'offline', 'UTM Johor Bahru Campus', 'MY', 107, '{4,9}', 'Program tiga minggu tentang sistem siber-fisik, edge computing, dan keamanan jaringan industri di UTM, dengan proyek kelompok pemantauan mesin berbasis sensor getaran.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Mohon unggah transkrip nilai UTM untuk B11249376 yang belum ada di berkas mobility, dan sesuaikan tanggal selesai dengan sertifikat (27 Agustus 2026).');
select pg_temp.bulk_pset(242, '{B11239558,B11249376,B11249731,B11249484}', '{}', '{PG557816}');
select pg_temp.bulk_act(243, 'Publikasi Bersama Material Komposit Daur Ulang untuk Manufaktur Aditif dengan University of Melbourne', 69, 37, 'outbound', '2026-08-03', '2026-09-18', 'online', 'Microsoft Teams', null, 181, '{9,12}', 'Penulisan dan pengiriman artikel bersama ke jurnal internasional bereputasi tentang karakterisasi filamen komposit daur ulang untuk manufaktur aditif, melalui rapat daring dua mingguan.', pg_temp.wib('2026-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Sarah Mitchell", "institution": "University of Melbourne", "country_code": "AU", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(244, 'Kuliah Tamu Large Language Models untuk Rekayasa Perangkat Lunak dari Xiamen University', 68, 15, 'inbound', '2026-11-09', '2026-11-10', 'offline', 'Auditorium Gedung P PCU', 'ID', 184, '{4,9}', 'Rencana kuliah tamu tentang pemanfaatan large language model untuk pembangkitan kode dan pengujian otomatis, disertai lokakarya praktik bagi mahasiswa Informatika.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Lin Hao", "institution": "Xiamen University", "country_code": "CN", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(245, 'Penyusunan Joint Curriculum Industrial Engineering bersama Chulalongkorn University', 67, 32, 'inbound', '2026-12-07', '2026-12-09', 'hybrid', 'Ruang Rapat Dekanat FTI Gedung P PCU', 'ID', 34, '{4,17}', 'Rencana lokakarya penyusunan kurikulum bersama program Industrial Engineering untuk skema double degree, mencakup pemetaan mata kuliah dan mekanisme penjaminan mutu.', null, null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Napat Wongsuwan", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]');

select pg_temp.bulk_verify(221, 245);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_2.sql
-- seed-supabase/10_kegiatan_tambahan_2 (simks-partnership): additional bulk kegiatan 246-270, adapted from the local
-- demo seed supabase/seed/04_bulk_2.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 25, 30, 31, 72, 77, 95, 105, 107, 126, 134, 143, 151, 181, 193, 195, 200. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{25,30,31,72,77,95,105,107,126,134,143,151,181,193,195,200}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_2: SIM Kerjasama agreements missing, kegiatan 246-270 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(246, 'Inbound Exchange Teknik Elektro dari Technische Hochschule Deggendorf 2025', 65, 2, 'inbound', '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 126, '{4,17}', 'Mahasiswa Technische Hochschule Deggendorf mengikuti satu semester perkuliahan di Prodi Teknik Elektro PCU, termasuk mata kuliah Sistem Tenaga Listrik dan Energi Terbarukan serta proyek laboratorium konversi energi. Kredit ditransfer ke program Elektrotechnik di Deggendorf.', pg_temp.wib('2025-12-23', '09:00'), 'approved', pg_temp.wib('2026-01-06', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(246, '{}', '{X06269006}', '{}');
select pg_temp.bulk_act(247, 'Kuliah Tamu Proteksi Sistem Tenaga dari Universitas Brawijaya', 65, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid', 'Gedung P PCU', 'ID', 193, '{4,7}', 'Kuliah tamu dosen Teknik Elektro Universitas Brawijaya mengenai koordinasi relai proteksi dan deteksi gangguan pada jaringan distribusi dengan penetrasi pembangkit tersebar tinggi. Diikuti mahasiswa mata kuliah Proteksi Sistem Tenaga secara luring dan daring.', pg_temp.wib('2025-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Hadi Suyono, S.T., M.T.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(248, 'Riset Bersama Optimasi PLTS Atap Kampus dengan Universiti Teknologi Malaysia', 65, 4, 'outbound', '2025-10-13', '2025-10-17', 'offline', 'Universiti Teknologi Malaysia, Johor Bahru', 'MY', 77, '{7,13}', 'Dosen Teknik Elektro melakukan pengukuran dan pemodelan kinerja PLTS atap di kampus UTM sebagai pembanding instalasi PCU. Tim menyusun metodologi optimasi sudut kemiringan dan jadwal pembersihan panel untuk iklim tropis lembap.', pg_temp.wib('2025-10-28', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Mohd Hafiz Abdullah", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(249, 'Short Program Robotika Otonom di Kanazawa Institute of Technology', 65, 23, 'outbound', '2025-11-03', '2025-11-14', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,9}', 'Program singkat dua minggu tentang navigasi robot bergerak otonom, sensor LiDAR, dan ROS 2 di Kanazawa Institute of Technology. Mahasiswa Teknik Elektro menyelesaikan proyek kelompok robot pengantar barang dan mempresentasikannya di laboratorium mitra.', pg_temp.wib('2025-11-21', '09:00'), 'approved', pg_temp.wib('2025-12-01', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(249, '{B12239256,B12229628,B12239294}', '{}', '{PG204517}');
select pg_temp.bulk_act(250, 'Seminar Teknologi Baterai Kendaraan Listrik bersama Universitas Indonesia', 65, 10, 'outbound', '2025-11-26', '2025-11-26', 'offline', 'Fakultas Teknik Universitas Indonesia, Depok', 'ID', 134, '{7,9,11}', 'Seminar bersama Fakultas Teknik Universitas Indonesia tentang sistem manajemen baterai (BMS), keamanan sel lithium-ion, dan infrastruktur pengisian kendaraan listrik di Indonesia. Dosen Teknik Elektro PCU menjadi pembicara sesi estimasi state-of-charge.', pg_temp.wib('2025-12-03', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Feri Yusivar, M.Eng.", "institution": "Universitas Indonesia", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(251, 'Kunjungan Akademik Laboratorium Sistem Tenaga Universitas Indonesia', 65, 27, 'outbound', '2025-12-08', '2025-12-10', 'offline', 'Departemen Teknik Elektro Universitas Indonesia, Depok', 'ID', 134, '{7,17}', 'Delegasi Teknik Elektro PCU mengunjungi laboratorium sistem tenaga dan elektronika daya Universitas Indonesia untuk menjajaki topik riset lanjutan serta pemanfaatan bersama fasilitas uji. Hasilnya berupa daftar topik riset bersama 2026.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ir. Rudy Setiabudy", "institution": "Universitas Indonesia", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(252, 'Riset Bersama Prakiraan Beban Listrik Berbasis Machine Learning dengan Universitas Gadjah Mada', 65, 4, 'outbound', '2025-08-18', '2025-10-31', 'online', 'Microsoft Teams', null, 72, '{7,9}', 'Riset daring bersama Departemen Teknik Elektro dan Teknologi Informasi UGM untuk membangun model prakiraan beban listrik jangka pendek pada jaringan distribusi kampus. Data smart meter PCU dibandingkan dengan data gardu kampus Bulaksumur; luaran berupa draf artikel jurnal dan model LSTM terbuka.', pg_temp.wib('2025-11-07', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Bambang Sugiyantoro, M.T.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(253, 'Credit Transfer Inbound Sistem Tertanam dari Kanazawa Institute of Technology 2025', 65, 33, 'inbound', '2025-10-01', '2026-01-23', 'offline', 'Laboratorium Sistem Tertanam PCU', 'ID', 105, '{4}', 'Mahasiswa Kanazawa Institute of Technology mengambil mata kuliah Sistem Tertanam, Mikrokontroler, dan Internet of Things di Teknik Elektro PCU dengan pengakuan kredit di institusi asal. Proyek akhir berupa node sensor kualitas udara berdaya rendah.', pg_temp.wib('2026-02-25', '09:00'), 'approved', pg_temp.wib('2026-03-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(253, '{}', '{X06269009}', '{}');
select pg_temp.bulk_act(254, 'Student Exchange Semester Genap Teknik Elektro di Hochschule Bremen', 65, 2, 'outbound', '2026-03-02', '2026-07-17', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7,17}', 'Tiga mahasiswa Teknik Elektro mengikuti satu semester di program Elektrotechnik Hochschule Bremen dengan fokus energi terbarukan dan elektronika daya. Mata kuliah yang diambil dikonversi ke kurikulum PCU.', pg_temp.wib('2026-07-24', '09:00'), 'approved', pg_temp.wib('2026-08-05', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(254, '{B12239153,B12249412,B12239792}', '{}', '{}');
select pg_temp.bulk_act(255, 'Inbound Exchange Teknik Mesin dari University of Melbourne Semester Genap 2026', 69, 2, 'inbound', '2026-03-02', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 181, '{4,7,17}', 'Mahasiswa University of Melbourne menjalani semester pertukaran di Teknik Mesin PCU dan bergabung dalam proyek pengering surya hibrida di Laboratorium Konversi Energi. Kegiatan juga mencakup kelas bahasa dan budaya Indonesia.', pg_temp.wib('2026-07-02', '09:00'), 'approved', pg_temp.wib('2026-07-10', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(255, '{}', '{X05269007}', '{}');
select pg_temp.bulk_act(256, 'Kuliah Tamu Keamanan Siber Smart Grid dari Universitas Gadjah Mada', 65, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Gedung P PCU', 'ID', 72, '{4,9}', 'Kuliah tamu dosen UGM tentang ancaman siber pada sistem SCADA dan advanced metering infrastructure, termasuk standar IEC 62351. Mahasiswa Teknik Elektro melakukan studi kasus serangan pada gardu induk digital.', pg_temp.wib('2026-03-17', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Eng. Sigit Basuki Wibowo", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(257, 'Riset Bersama Inverter Grid-Forming Mikrogrid dengan NTUST', 65, 4, 'outbound', '2026-04-20', '2026-04-24', 'offline', 'National Taiwan University of Science and Technology, Taipei', 'TW', 200, '{7,9}', 'Riset bersama National Taiwan University of Science and Technology untuk pengembangan kontrol inverter grid-forming berbasis mikrokontroler DSP pada mikrogrid kampus. Pengujian hardware-in-the-loop dilakukan di laboratorium elektronika daya mitra.', pg_temp.wib('2026-05-04', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Chen Wei-Lun", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(258, 'Pelatihan Daring PLC dan SCADA bersama Universitas Brawijaya', 65, 69, 'outbound', '2026-08-17', '2026-08-19', 'online', 'Zoom Meeting', null, 193, '{4,9}', 'Pelatihan daring tiga hari oleh instruktur Universitas Brawijaya tentang pemrograman PLC IEC 61131-3 dan perancangan HMI SCADA untuk dosen dan laboran Teknik Elektro. Peserta menyelesaikan studi kasus kontrol stasiun pompa.', pg_temp.wib('2026-08-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rini Nur Hasanah, S.T., M.Sc.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(259, 'Magang Riset Robot Kolaboratif Berbasis Visi Komputer di Yonsei University', 65, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline', 'Yonsei University, Sinchon Campus, Seoul', 'KR', 143, '{4,8,9}', 'Magang riset delapan minggu di laboratorium robotika Yonsei University untuk pengembangan lengan robot kolaboratif dengan kendali berbasis visi komputer. Mahasiswa Teknik Elektro menyusun laporan teknis dan demo akhir.', pg_temp.wib('2026-07-29', '09:00'), 'approved', pg_temp.wib('2026-08-07', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(259, '{B12249256,B12249376,B12239075}', '{}', '{}');
select pg_temp.bulk_act(260, 'Inbound Short Program Energi Terbarukan Universiti Teknologi Malaysia 2026', 65, 23, 'inbound', '2026-07-06', '2026-07-17', 'offline', 'Laboratorium Konversi Energi PCU', 'ID', 107, '{4,7}', 'Program singkat dua minggu bagi mahasiswa Universiti Teknologi Malaysia tentang sistem PLTS, turbin angin skala kecil, dan audit energi bangunan. Peserta melakukan kunjungan lapangan ke instalasi PLTS atap di Surabaya.', pg_temp.wib('2026-07-22', '09:00'), 'approved', pg_temp.wib('2026-07-31', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(260, '{}', '{X06269010}', '{}');
select pg_temp.bulk_act(261, 'Pengabdian Masyarakat PLTS Off-Grid Desa bersama Universitas Brawijaya', 65, 40, 'outbound', '2026-02-23', '2026-02-27', 'offline', 'Desa Sidomulyo, Kabupaten Pacitan', 'ID', 193, '{1,7}', 'Dosen dan mahasiswa Teknik Elektro PCU bersama tim Universitas Brawijaya memasang PLTS off-grid 3 kWp untuk balai desa dan pompa air, serta melatih warga melakukan perawatan dasar panel dan baterai. Luaran berupa sistem terpasang dan modul perawatan.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Ir. Teguh Utomo, M.T.", "institution": "Universitas Brawijaya", "country_code": "ID", "role": "other"}]', p_co_units => '{28}');
select pg_temp.bulk_act(262, 'Joint Curriculum Telekomunikasi 5G dengan Kanazawa Institute of Technology', 65, 32, 'inbound', '2026-04-13', '2026-04-15', 'hybrid', 'Gedung P PCU', 'ID', 95, '{4,9}', 'Lokakarya penyusunan mata kuliah bersama Jaringan 5G dan Antena Gelombang Milimeter dengan Kanazawa Institute of Technology. Kedua pihak menyepakati capaian pembelajaran, modul praktikum, dan skema kuliah bersama mulai Ganjil 2026/2027.', pg_temp.wib('2026-04-21', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Takeshi Nakamura", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "visiting_lecturer"}]', p_co_units => '{28}');
select pg_temp.bulk_act(263, 'Inbound Exchange Kendaraan Listrik Yonsei University Semester Genap 2026', 69, 2, 'inbound', '2026-02-09', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}', 'Mahasiswa Yonsei University mengikuti satu semester di Teknik Mesin PCU dengan mata kuliah Kendaraan Listrik dan Sistem Penggerak serta proyek konversi sepeda motor listrik. Pengakuan kredit dilakukan oleh Yonsei University.', pg_temp.wib('2026-08-04', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(263, '{}', '{X05269008}', '{}');
select pg_temp.bulk_act(264, 'Kunjungan Akademik Fakultas Teknik Chulalongkorn University', 65, 27, 'outbound', '2026-08-24', '2026-08-26', 'offline', 'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 151, '{4,17}', 'Kunjungan pimpinan Teknik Elektro ke Chulalongkorn University untuk menindaklanjuti MoU: peninjauan laboratorium smart grid dan telekomunikasi serta penyusunan rencana pertukaran mahasiswa dan dosen 2027.', pg_temp.wib('2026-09-02', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Wongsiri", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(265, 'Summer Program Robotics and Automation di Chulalongkorn University', 65, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn University Faculty of Engineering, Bangkok', 'TH', 25, '{4,9}', 'Program musim panas dua minggu tentang otomasi industri, PLC, dan robot industri. Mahasiswa Teknik Elektro mengerjakan proyek sel manufaktur otomatis bersama mahasiswa Chulalongkorn University.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(265, '{B12239256,B12229628,B12239294,B12239153,B12249412}', '{}', '{PG707752}');
select pg_temp.bulk_act(266, 'Studi Ekskursi Teknologi Telekomunikasi 5G ke National Taiwan University', 65, 24, 'outbound', '2026-09-07', '2026-09-11', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,9}', 'Studi ekskursi lima hari ke laboratorium komunikasi nirkabel National Taiwan University dan operator telekomunikasi di Taipei. Mahasiswa mengamati pengujian antena 5G dan menyusun laporan perbandingan infrastruktur jaringan.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(266, '{B12239792,B12249256,B12249376}', '{}', '{PG413450}');
select pg_temp.bulk_act(267, 'Magang Riset Powertrain Kendaraan Listrik di University of Melbourne', 69, 21, 'outbound', '2026-07-06', '2026-08-28', 'offline', 'University of Melbourne, Parkville Campus', 'AU', 181, '{8,9,11}', 'Magang delapan minggu di laboratorium e-mobility University of Melbourne, mencakup pengujian motor traksi, manajemen termal baterai, dan pengisi daya DC cepat. Mahasiswa Teknik Mesin menyusun laporan magang dan poster hasil pengujian.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(8, '14:00'), p_mnote => 'Sertifikat magang dari University of Melbourne dan transkrip konversi SKS belum diunggah untuk kedua mahasiswa. Mohon lengkapi berkas mobilitas sebelum diajukan ulang.', p_co_units => '{28}');
select pg_temp.bulk_pset(267, '{B14239757,B14229309}', '{}', '{}');
select pg_temp.bulk_act(268, 'Seminar Internasional Transisi Energi Terbarukan bersama Universiti Teknologi Malaysia', 65, 10, 'inbound', '2026-09-16', '2026-09-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 77, '{7,13,17}', 'Seminar internasional tentang integrasi energi terbarukan ke jaringan listrik Indonesia dan Malaysia, penyimpanan energi, dan kebijakan net-zero. Menghadirkan pembicara UTM dan dosen Teknik Elektro PCU dengan lebih dari 200 peserta.', pg_temp.wib('2026-09-22', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ahmad Faizal Rahman", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "speaker"}]', p_co_units => '{28}');
select pg_temp.bulk_act(269, 'Workshop Persiapan Kontes Robot Sepak Bola Beroda bersama Universitas Gadjah Mada', 65, 35, 'inbound', '2026-11-09', '2026-11-11', 'offline', 'Laboratorium Robotika PCU', 'ID', 72, '{4,9}', 'Rencana lokakarya bersama persiapan kontes robot sepak bola beroda, meliputi desain mekanik, kendali motor, dan strategi multi-agen. Tim robotika UGM akan berbagi pengalaman mengikuti Kontes Robot Indonesia.', null, null, null, p_files => '{ia}', p_co_units => '{28}');
select pg_temp.bulk_act(270, 'Credit Transfer Teknik Elektro ke Hochschule Bremen Ganjil 2026/2027', 65, 33, 'outbound', '2026-10-05', '2027-01-29', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7}', 'Rencana program transfer kredit satu semester di Hochschule Bremen untuk mata kuliah Sistem Tenaga Lanjut dan Penyimpanan Energi. Draf menunggu konfirmasi letter of acceptance dari mitra.', null, null, null, p_files => '{}', p_co_units => '{28}');
select pg_temp.bulk_pset(270, '{B12249585,B12239075}', '{}', '{}');

select pg_temp.bulk_verify(246, 270);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_3.sql
-- seed-supabase/10_kegiatan_tambahan_3 (simks-partnership): additional bulk kegiatan 271-295, adapted from the local
-- demo seed supabase/seed/04_bulk_3.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 15, 25, 30, 31, 70, 100, 112, 127, 143, 156, 158, 159, 160, 166, 167, 174. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{15,25,30,31,70,100,112,127,143,156,158,159,160,166,167,174}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_3: SIM Kerjasama agreements missing, kegiatan 271-295 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(271, 'Riset Bersama Sustainability Reporting UMKM Manufaktur dengan Universitas Pelita Harapan', 6, 4, 'outbound', '2025-09-01', '2025-12-15', 'offline', 'Fakultas Ekonomi dan Bisnis Universitas Pelita Harapan, Tangerang', 'ID', 112, '{12,8,17}', 'Penelitian bersama untuk menyusun model pelaporan keberlanjutan sederhana berbasis standar GRI bagi UMKM manufaktur di Jawa Timur dan Banten. Luaran berupa instrumen pengungkapan ESG dan draf artikel jurnal bersama.', pg_temp.wib('2025-12-19', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rizky Aditya Wibisono, S.E., M.Ak.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "researcher", "notes": "Peneliti utama dari Program Studi Akuntansi FEB UPH"}]', p_co_units => '{4}');
select pg_temp.bulk_act(272, 'Student Exchange Akuntansi Yonsei School of Business Fall 2025', 6, 2, 'outbound', '2025-09-01', '2025-12-19', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 143, '{4,17}', 'Tiga mahasiswa Akuntansi mengikuti satu semester perkuliahan di Yonsei School of Business, termasuk mata kuliah International Financial Reporting dan Managerial Accounting. Nilai dikonversi ke kurikulum Prodi Akuntansi PCU.', pg_temp.wib('2026-01-06', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(272, '{D32249150,D32259472,D32249331}', '{}', '{}');
select pg_temp.bulk_act(273, 'Kuliah Tamu International Taxation and Transfer Pricing dari National Taiwan University', 5, 15, 'inbound', '2025-10-22', '2025-10-22', 'offline', 'Auditorium Gedung W PCU', 'ID', 30, '{4,8,17}', 'Kuliah tamu bagi mahasiswa Manajemen dan Akuntansi tentang perpajakan internasional, BEPS, dan dokumentasi transfer pricing pada grup usaha Taiwan–Indonesia. Diikuti sekitar 180 mahasiswa.', pg_temp.wib('2025-11-03', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Chen Wei-Ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker", "notes": "Department of Accounting, College of Management"}]', p_co_units => '{6}');
select pg_temp.bulk_act(274, 'Short Program Hospitality & Tourism Management di KMUTT Bangkok', 5, 23, 'outbound', '2025-11-10', '2025-11-21', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 156, '{8,4}', 'Program singkat dua minggu tentang manajemen hospitality, revenue management hotel, dan pariwisata berkelanjutan di Thailand, dilengkapi kunjungan industri ke hotel dan operator wisata di Bangkok.', pg_temp.wib('2025-12-02', '09:00'), 'approved', pg_temp.wib('2025-12-10', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(274, '{D31249692,D31239726,D31229821,D31229027}', '{}', '{}');
select pg_temp.bulk_act(275, 'Online Course Sustainable Finance and ESG Investing bersama University of Amsterdam', 5, 79, 'outbound', '2025-10-01', '2025-11-26', 'online', 'Microsoft Teams', null, 166, '{13,8,4}', 'Kursus daring delapan pertemuan mengenai keuangan berkelanjutan, analisis skor ESG, dan green bonds yang diampu dosen Amsterdam Business School. Peserta menyusun analisis portofolio ESG sebagai tugas akhir.', pg_temp.wib('2025-12-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maarten de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer", "notes": "Amsterdam Business School"}]', p_co_units => '{4}');
select pg_temp.bulk_act(276, 'International Conference on Accounting and Sustainable Finance (ICASF) 2025', 6, 10, 'inbound', '2025-11-27', '2025-11-28', 'hybrid', 'Gedung P PCU', 'ID', 112, '{8,12,17}', 'Konferensi internasional dua hari yang diselenggarakan School of Business and Management PCU bersama FEB Universitas Pelita Harapan dengan 64 makalah tentang akuntansi keberlanjutan, tata kelola, dan keuangan hijau. Prosiding terbit dengan ISBN.', pg_temp.wib('2025-12-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Dian Kartikasari, S.E., M.Si., Ak.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "speaker", "notes": "Keynote speaker"}, {"full_name": "Dr. Bagus Hendra Saputra, S.E., M.M.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "speaker"}]', p_co_units => '{5,4}');
select pg_temp.bulk_act(277, 'Inbound Exchange Curtin Business School di Prodi Akuntansi Semester Ganjil 2025/2026', 6, 2, 'inbound', '2025-09-01', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 160, '{4,17}', 'Mahasiswa Curtin Business School mengikuti satu semester perkuliahan di PCU, termasuk mata kuliah Asian Business Environment, Akuntansi Keuangan Lanjutan, dan Bahasa Indonesia untuk Penutur Asing.', pg_temp.wib('2026-01-27', '09:00'), 'approved', pg_temp.wib('2026-02-05', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(277, '{}', '{X05259014}', '{}');
select pg_temp.bulk_act(278, 'Pendampingan Pembukuan Digital UMKM Kuliner Siwalankerto bersama Universitas Negeri Surabaya', 5, 40, 'outbound', '2026-01-05', '2026-01-23', 'offline', 'Balai RW Kelurahan Siwalankerto, Surabaya', 'ID', 70, '{1,8,10}', 'Dosen dan mahasiswa Manajemen bersama tim Fakultas Ekonomika dan Bisnis Unesa mendampingi 25 pelaku UMKM kuliner menyusun pembukuan sederhana dengan aplikasi akuntansi gratis serta memisahkan keuangan usaha dan rumah tangga.', pg_temp.wib('2026-02-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nurul Hidayati, S.E., M.Ak.", "institution": "Universitas Negeri Surabaya", "country_code": "ID", "role": "other", "notes": "Koordinator pengabdian masyarakat FEB Unesa"}]', p_co_units => '{4}');
select pg_temp.bulk_act(279, 'Inbound Exchange Yonsei University Spring 2026 di School of Business and Management', 6, 2, 'inbound', '2026-02-02', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}', 'Mahasiswa Yonsei University mengikuti semester genap di PCU dengan fokus pada akuntansi manajemen dan kewirausahaan di pasar Asia Tenggara, termasuk proyek konsultasi untuk UMKM Surabaya.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-06-30', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(279, '{}', '{X06259015}', '{}');
select pg_temp.bulk_act(280, 'Kunjungan Akademik Chulalongkorn Business School ke PCU 2026', 5, 27, 'inbound', '2026-02-24', '2026-02-25', 'offline', 'Gedung P PCU', 'ID', 25, '{4,17}', 'Delegasi Chulalongkorn Business School membahas benchmarking kurikulum International Business, skema transfer kredit, dan rencana penambahan kuota pertukaran mahasiswa untuk tahun akademik 2026/2027.', pg_temp.wib('2026-03-06', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Pornchai Wongsawat", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "International Affairs Coordinator, Chulalongkorn Business School"}, {"full_name": "Dr. Natthaya Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Director, BBA International Program"}]', p_co_units => '{4}');
select pg_temp.bulk_act(281, 'Short Program Indonesian Business Culture untuk Mahasiswa Taylor''s University', 5, 23, 'inbound', '2026-03-02', '2026-03-13', 'offline', 'Gedung P PCU', 'ID', 167, '{4,8,17}', 'Program singkat dua minggu bagi mahasiswa Taylor''s Business School tentang budaya bisnis Indonesia, praktik bisnis keluarga Tionghoa-Indonesia, dan kunjungan perusahaan di Surabaya dan Gresik.', pg_temp.wib('2026-03-20', '09:00'), 'approved', pg_temp.wib('2026-03-27', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(281, '{}', '{X06269012}', '{}');
select pg_temp.bulk_act(282, 'Magang Hospitality Management di Taipei melalui National Taiwan University', 5, 21, 'outbound', '2026-02-02', '2026-04-30', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{8,4}', 'Magang tiga bulan di hotel mitra National Taiwan University di Taipei pada divisi front office, F&B, dan revenue management. Mahasiswa menyusun laporan magang yang diakui sebagai mata kuliah Magang Industri.', pg_temp.wib('2026-05-12', '09:00'), 'approved', pg_temp.wib('2026-05-20', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(282, '{D31229451,D31239549,D31249207}', '{}', '{}');
select pg_temp.bulk_act(283, 'Publikasi Bersama Kepatuhan Pajak UMKM Indonesia–Korea dengan Yonsei University', 5, 37, 'outbound', '2026-02-16', '2026-05-29', 'online', 'Microsoft Teams', null, 31, '{8,16,17}', 'Penulisan artikel bersama tentang faktor kepatuhan pajak UMKM di Indonesia dan Korea Selatan menggunakan data survei kedua negara. Naskah dikirim ke jurnal internasional bereputasi (Scopus Q2).', pg_temp.wib('2026-06-08', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Park Min-jae", "institution": "Yonsei University", "country_code": "KR", "role": "researcher", "notes": "Yonsei School of Business"}]', p_co_units => '{6}');
select pg_temp.bulk_act(284, 'Workshop Lean Startup dan Business Model Validation bersama Fontys', 5, 35, 'inbound', '2026-03-18', '2026-03-19', 'hybrid', 'Gedung P PCU', 'ID', 159, '{8,9,4}', 'Workshop kewirausahaan dua hari bagi mahasiswa inkubator bisnis PCU tentang validasi model bisnis, customer discovery, dan penyusunan pitch deck, difasilitasi pelatih dari Fontys Centre for Entrepreneurship.', pg_temp.wib('2026-03-30', '09:00'), null, null, p_ext => '[{"full_name": "Lotte van den Berg, MBA", "institution": "Fontys University of Applied Sciences", "country_code": "NL", "role": "speaker", "notes": "Fontys Centre for Entrepreneurship"}]', p_co_units => '{4}');
select pg_temp.bulk_act(285, 'Pengembangan Kurikulum Bersama Akuntansi Keberlanjutan dengan National Taiwan University', 6, 11, 'outbound', '2026-04-13', '2026-04-17', 'offline', 'NTU College of Management, Taipei', 'TW', 15, '{4,12,13}', 'Tim dosen Akuntansi menyusun bersama silabus mata kuliah Sustainability Accounting and Assurance yang akan ditawarkan di kedua universitas, termasuk studi kasus perusahaan Taiwan dan Indonesia.', pg_temp.wib('2026-04-28', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Lin Hsiao-Mei", "institution": "National Taiwan University", "country_code": "TW", "role": "other", "notes": "Department of Accounting, NTU College of Management"}]', p_co_units => '{4}');
select pg_temp.bulk_act(286, 'Studi Ekskursi Pasar Modal dan Fintech Seoul bersama Yonsei University', 6, 24, 'outbound', '2026-05-11', '2026-05-16', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{8,9,4}', 'Kunjungan studi mahasiswa Akuntansi ke Korea Exchange, perusahaan fintech di Seoul, dan kelas bersama di Yonsei School of Business tentang regulasi pasar modal dan pelaporan keuangan digital.', pg_temp.wib('2026-05-26', '09:00'), 'approved', pg_temp.wib('2026-06-03', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(286, '{D32229204,D32239758,D32249505,D32259900,D32229279,D32249196,D32259976}', '{}', '{}');
select pg_temp.bulk_act(287, 'Kuliah Tamu Forensic Accounting dan Pencegahan Fraud dari Universitas Surabaya', 6, 7, 'inbound', '2026-06-03', '2026-06-03', 'offline', 'Auditorium Gedung W PCU', 'ID', 158, '{16,4}', 'Kuliah tamu tentang teknik akuntansi forensik, red flag kecurangan laporan keuangan, dan studi kasus investigasi fraud di BUMN bagi mahasiswa Akuntansi semester enam.', pg_temp.wib('2026-07-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Hendra Gunawan Sutrisno, S.E., M.Ak., CFrA", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker", "notes": "Fakultas Bisnis dan Ekonomika Ubaya"}]', p_co_units => '{4}');
select pg_temp.bulk_act(288, 'Short Program Global Supply Chain & Logistics di Chulalongkorn University', 5, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn Business School, Bangkok', 'TH', 25, '{9,8,4}', 'Program singkat dua minggu tentang manajemen rantai pasok global, logistik ASEAN, dan kunjungan ke Laem Chabang Port serta pusat distribusi di Bangkok bagi mahasiswa Manajemen.', pg_temp.wib('2026-08-24', '09:00'), 'approved', pg_temp.wib('2026-09-01', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(288, '{D31249692,D31239726,D31229821,D31229027,D31229451}', '{}', '{}');
select pg_temp.bulk_act(289, 'Cultural Exchange Bisnis Keluarga Taiwan bersama National Taiwan University', 5, 29, 'outbound', '2026-08-24', '2026-09-04', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,8,17}', 'Pertukaran budaya dua minggu untuk mempelajari tata kelola dan suksesi bisnis keluarga Taiwan melalui kelas bersama, kunjungan perusahaan keluarga, dan homestay di Taipei.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(289, '{D31239726,D31229027,D31249207,D31249746}', '{}', '{}');
select pg_temp.bulk_act(290, 'Academic Exchange Mahasiswa Universiti Brunei Darussalam di PCU 2026', 5, 28, 'inbound', '2026-08-17', '2026-09-18', 'offline', 'Gedung P PCU', 'ID', 174, '{4,17}', 'Mahasiswa UBD School of Business and Economics mengikuti perkuliahan Bisnis Internasional dan Akuntansi Perpajakan selama lima minggu serta proyek riset kecil tentang investasi Brunei di Jawa Timur.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(290, '{}', '{X05259013}', '{}');
select pg_temp.bulk_act(291, 'Program Imersi Accounting Analytics dan Audit Berbasis Data di Yonsei University', 5, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,9}', 'Program imersi dua minggu tentang analitik data akuntansi, audit berbasis data, dan visualisasi keuangan dengan Python dan Power BI di Yonsei School of Business.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '09:00'), p_mnote => 'Transkrip nilai dua mahasiswa belum diunggah dan surat keterangan selesai program dari Yonsei University belum ditandatangani. Mohon lengkapi bundel mobilitas lalu ajukan ulang.', p_co_units => '{6}');
select pg_temp.bulk_pset(291, '{D31239549,D31249207,D31259757,D31249746,D31239185}', '{}', '{}');
select pg_temp.bulk_act(292, 'Seminar Nasional Perpajakan Digital dan Coretax Administration System', 6, 10, 'inbound', '2026-09-09', '2026-09-09', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 158, '{16,8,17}', 'Seminar nasional tentang implementasi Coretax DJP, e-Faktur generasi baru, dan dampaknya bagi praktik akuntansi perusahaan, menghadirkan akademisi Ubaya dan praktisi perpajakan korporasi dari PT Sampoerna Strategic Square.', pg_temp.wib('2026-09-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Agus Widodo Prasetyo, S.E., M.Ak., BKP", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker"}, {"full_name": "Yohanes Setiadi, S.E., M.Ak., BKP", "institution": "PT Sampoerna Strategic Square", "country_code": "ID", "role": "speaker", "notes": "Tax Manager"}]', p_co_units => '{5}');
select pg_temp.bulk_act(293, 'Faculty Exchange Dosen Corporate Finance PCU di Fontys Venlo', 5, 31, 'outbound', '2026-09-14', '2026-09-25', 'offline', 'Fontys Venlo Campus', 'NL', 100, '{4,17}', 'Dua dosen Keuangan Prodi Manajemen mengajar modul Corporate Finance in Emerging Markets di Fontys Venlo dan menjajaki penelitian bersama tentang pembiayaan UKM di Indonesia dan Belanda.', pg_temp.wib('2026-09-29', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Thomas Janssen", "institution": "Fontys University of Applied Sciences", "country_code": "NL", "role": "other", "notes": "Host lecturer Fontys Venlo"}]', p_co_units => '{4}');
select pg_temp.bulk_act(294, 'Riset Bersama Integrated Reporting Perusahaan Keluarga dengan National Taiwan University', 6, 4, 'outbound', '2026-11-02', '2027-01-29', 'hybrid', 'NTU College of Management, Taipei', 'TW', 15, '{12,8,17}', 'Rencana riset bersama tentang penerapan integrated reporting dan pengungkapan keberlanjutan pada perusahaan keluarga tercatat di Bursa Efek Indonesia dan Taiwan Stock Exchange.', null, null, null, p_files => '{ia}', p_co_units => '{4}');
select pg_temp.bulk_act(295, 'Kuliah Tamu Hotel Revenue Management dari KMUTT', 5, 15, 'inbound', '2026-09-30', '2026-09-30', 'online', 'Zoom Meeting', null, 127, '{8,4}', 'Kuliah tamu daring tentang strategi dynamic pricing, forecasting okupansi, dan distribusi kanal online pada industri perhotelan Thailand bagi mahasiswa Manajemen konsentrasi hospitality.', null, null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Siriporn Chaiyaporn", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]', p_co_units => '{4}');

select pg_temp.bulk_verify(271, 295);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_4.sql
-- seed-supabase/10_kegiatan_tambahan_4 (simks-partnership): additional bulk kegiatan 296-320, adapted from the local
-- demo seed supabase/seed/04_bulk_4.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 12, 15, 25, 28, 30, 31, 62, 65, 123, 152, 166, 168, 174, 180. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{12,15,25,28,30,31,62,65,123,152,166,168,174,180}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_4: SIM Kerjasama agreements missing, kegiatan 296-320 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(296, 'Kuliah Tamu Digital Marketing Strategy in the K-Wave Era dari Yonsei School of Business', 5, 15, 'inbound', '2025-10-22', '2025-10-22', 'offline', 'Auditorium Gedung W PCU', 'ID', 31, '{4,8}', 'Kuliah tamu bagi mahasiswa mata kuliah Pemasaran Digital tentang strategi pemasaran merek Korea memanfaatkan Hallyu dan influencer marketing. Diikuti sekitar 180 mahasiswa Manajemen dan ditutup dengan studi kasus kampanye K-beauty di Asia Tenggara.', pg_temp.wib('2025-10-29', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Kim Jae-won, Ph.D.", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(297, 'Student Exchange HKBU School of Business Semester Fall 2025', 5, 2, 'outbound', '2025-08-25', '2025-12-19', 'offline', 'Hong Kong Baptist University, Kowloon Tong', 'HK', 62, '{4,17}', 'Tiga mahasiswa Manajemen mengikuti satu semester perkuliahan di School of Business Hong Kong Baptist University dengan fokus mata kuliah International Marketing dan Consumer Behavior. Nilai dikonversi ke kurikulum Prodi Manajemen sebagai mata kuliah pilihan internasional.', pg_temp.wib('2026-01-07', '09:00'), 'approved', pg_temp.wib('2026-01-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(297, '{D31239083,D31239791,D31239881}', '{}', '{}');
select pg_temp.bulk_act(298, 'Inbound Exchange University of Amsterdam di Prodi Manajemen PCU Semester Ganjil 2025', 5, 2, 'inbound', '2025-08-18', '2025-12-12', 'offline', 'Gedung P PCU', 'ID', 166, '{4,17}', 'Mahasiswa Amsterdam Business School, University of Amsterdam, mengikuti perkuliahan semester ganjil di Prodi Manajemen PCU, termasuk mata kuliah Indonesian Business Environment dan Entrepreneurship. Kegiatan dilengkapi program buddy dan kunjungan industri ke kawasan SIER Surabaya.', pg_temp.wib('2025-12-18', '09:00'), 'approved', pg_temp.wib('2025-12-29', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(298, '{}', '{X05259020}', '{}');
select pg_temp.bulk_act(299, 'Riset Bersama Ketahanan Rantai Pasok UMKM Pangan Olahan dengan FEB UGM', 5, 4, 'outbound', '2025-10-20', '2025-12-31', 'hybrid', 'Fakultas Ekonomika dan Bisnis UGM', 'ID', 28, '{2,9,12}', 'Penelitian bersama mengenai ketahanan rantai pasok UMKM pangan olahan di Jawa Timur dan DIY melalui survei 120 pelaku usaha. Luaran berupa model pemetaan risiko pemasok dan draf artikel untuk jurnal terakreditasi SINTA 2.', pg_temp.wib('2026-02-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rangga Almahendra", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(300, 'Pengabdian Masyarakat Digitalisasi Pemasaran Kampung Batik Jetis bersama Unair', 5, 40, 'outbound', '2025-10-11', '2025-11-22', 'offline', 'Kampung Batik Jetis Sidoarjo', 'ID', 180, '{1,8,17}', 'Pendampingan 25 perajin batik Jetis dalam pembuatan katalog digital, pengelolaan akun marketplace, dan pencatatan penjualan sederhana. Dilaksanakan bersama dosen FEB Universitas Airlangga dalam enam kali pertemuan lapangan.', pg_temp.wib('2025-11-28', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Gancar Candra Premananto", "institution": "Universitas Airlangga", "country_code": "ID", "role": "other"}]', p_co_units => '{4}');
select pg_temp.bulk_act(301, 'Pelatihan Digital Business Analytics bersama Telkom Indonesia', 5, 69, 'inbound', '2025-10-15', '2025-10-16', 'offline', 'Lab Komputer Manajemen Gedung P PCU', 'ID', 152, '{4,9}', 'Pelatihan dua hari bagi mahasiswa dan dosen Manajemen tentang analitik data pelanggan, dashboard penjualan, dan pemanfaatan big data telekomunikasi untuk segmentasi pasar. Instruktur berasal dari unit Digital Business Telkom Indonesia.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Andika Pratama, M.M.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Rizky Amalia, S.T., M.B.A.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(302, 'Magang Marketing & Customer Experience di Astra International Surabaya 2025', 5, 21, 'outbound', '2025-09-01', '2025-12-31', 'offline', 'PT Astra International Tbk, Kantor Wilayah Surabaya', 'ID', 123, '{8,9}', 'Tiga mahasiswa Manajemen tingkat akhir menjalani magang empat bulan di divisi Marketing dan Customer Experience Astra International wilayah Surabaya. Mahasiswa terlibat dalam analisis kepuasan pelanggan purnajual dan penyusunan materi kampanye produk korporat.', pg_temp.wib('2026-01-09', '09:00'), 'approved', pg_temp.wib('2026-01-20', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(302, '{D31229852,D31229748,D31229309}', '{}', '{}');
select pg_temp.bulk_act(303, 'Kuliah Bersama Human Resource Analytics dengan Yonsei University', 5, 34, 'inbound', '2025-11-05', '2025-12-10', 'online', 'Zoom Meeting', null, 31, '{4,8}', 'Enam sesi kuliah bersama daring untuk mata kuliah Manajemen SDM Strategik yang membahas people analytics, prediksi turnover, dan desain sistem kinerja. Mahasiswa PCU dan Yonsei mengerjakan tugas kelompok lintas negara.', pg_temp.wib('2025-12-15', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Lee Min-ji, Ph.D.", "institution": "Yonsei University", "country_code": "KR", "role": "visiting_lecturer"}]', p_co_units => '{4}');
select pg_temp.bulk_act(304, 'Student Exchange Yonsei School of Business Spring Semester 2026', 5, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,17}', 'Empat mahasiswa Manajemen mengikuti semester musim semi di Yonsei School of Business dengan mata kuliah Digital Business Strategy, Supply Chain Management, dan Korean Language I. Hasil studi diakui sebagai 20 SKS.', pg_temp.wib('2026-06-29', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(304, '{D31249994,D31249546,D31239043,D31249493}', '{}', '{}');
select pg_temp.bulk_act(305, 'Inbound Exchange National Taiwan University Spring 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-23', '2026-06-12', 'offline', 'Gedung P PCU', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengikuti semester genap di Prodi Manajemen PCU dengan mata kuliah Marketing Management, Bahasa Indonesia untuk Penutur Asing, dan Family Business. Program dilengkapi pendampingan buddy mahasiswa.', pg_temp.wib('2026-06-19', '09:00'), 'approved', pg_temp.wib('2026-06-26', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(305, '{}', '{X06259017}', '{}');
select pg_temp.bulk_act(306, 'Inbound Exchange HKBU dan Manipal Spring 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Gedung P PCU', 'ID', 62, '{4,17}', 'Mahasiswa Hong Kong Baptist University dan Manipal Academy of Higher Education mengikuti perkuliahan semester genap di Prodi Manajemen, khususnya mata kuliah Operations Management dan Southeast Asian Business, dalam kerangka MoU tiga pihak.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-02', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(306, '{}', '{X05269018,X05259019}', '{}');
select pg_temp.bulk_act(307, 'Kuliah Tamu Sustainable Supply Chain Management dari FEB UGM', 5, 15, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Auditorium Gedung W PCU', 'ID', 28, '{9,12,17}', 'Kuliah tamu tentang praktik rantai pasok berkelanjutan, green procurement, dan pengukuran jejak karbon logistik bagi mahasiswa konsentrasi Operasi dan Rantai Pasok. Dihadiri sekitar 150 mahasiswa dan dosen.', pg_temp.wib('2026-03-16', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Eko Suwardi", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(308, 'Sertifikasi Digital Marketing Associate bersama Telkom Indonesia', 5, 44, 'inbound', '2026-04-18', '2026-04-19', 'offline', 'Lab Komputer Manajemen Gedung P PCU', 'ID', 152, '{4,8}', 'Program sertifikasi kompetensi pemasaran digital bagi 40 mahasiswa Manajemen yang mencakup SEO, iklan media sosial, dan analitik kampanye. Ujian sertifikasi diselenggarakan oleh asesor Telkom Corporate University.', pg_temp.wib('2026-04-24', '09:00'), null, null, p_ext => '[{"full_name": "Dimas Aditya, S.Kom., M.M.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{4}');
select pg_temp.bulk_act(309, 'Studi Ekskursi Manajemen Operasi ke Astra International Jakarta', 5, 24, 'outbound', '2026-05-12', '2026-05-15', 'offline', 'Kantor Pusat PT Astra International Tbk, Sunter Jakarta', 'ID', 12, '{4,9}', 'Kunjungan studi empat hari ke kantor pusat dan fasilitas produksi grup Astra di Jakarta untuk mempelajari manajemen operasi, lean production, dan layanan pelanggan. Mahasiswa menyusun laporan observasi proses bisnis.', pg_temp.wib('2026-05-22', '09:00'), 'approved', pg_temp.wib('2026-05-29', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(309, '{D31259442,D31239676,D31249971,D31249923,D31249797,D31239469}', '{}', '{}');
select pg_temp.bulk_act(310, 'Publikasi Bersama Perilaku Konsumen Produk Halal dengan FEB UGM', 5, 37, 'outbound', '2026-02-02', '2026-05-29', 'online', 'Microsoft Teams', null, 28, '{4,12}', 'Penulisan artikel bersama tentang niat beli konsumen milenial terhadap produk makanan halal kemasan di Surabaya dan Yogyakarta. Naskah disusun bersama dosen FEB UGM dan dikirim ke Journal of Islamic Marketing.', pg_temp.wib('2026-06-08', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Sahabudin Sidiq, M.A.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(311, 'Pengembangan Kurikulum Kewirausahaan Digital MBKM bersama Binus University', 5, 11, 'inbound', '2026-03-02', '2026-04-30', 'hybrid', 'Ruang Rapat Prodi Manajemen Gedung P PCU', 'ID', 65, '{4,8}', 'Rangkaian lokakarya penyusunan paket mata kuliah Kewirausahaan Digital 20 SKS untuk skema MBKM yang dapat diambil lintas kampus bersama Binus Entrepreneurship Center. Luaran berupa RPS, rubrik penilaian proyek, dan skema rekognisi SKS bersama.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rini Setiowati, S.E., M.M.", "institution": "Universitas Bina Nusantara", "country_code": "ID", "role": "visiting_lecturer"}]', p_co_units => '{4}');
select pg_temp.bulk_act(312, 'Yonsei International Summer School 2026 Global Marketing Track', 5, 23, 'outbound', '2026-06-29', '2026-07-24', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,17}', 'Empat mahasiswa Manajemen mengikuti program musim panas empat minggu di Yonsei University pada jalur Global Marketing, termasuk kunjungan perusahaan ke CJ ENM dan Amorepacific. Diakui sebagai 6 SKS mata kuliah pilihan.', pg_temp.wib('2026-08-04', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(312, '{D31239820,D31249725,D31249029,D31239881}', '{}', '{}');
select pg_temp.bulk_act(313, 'Seminar Manajemen SDM di Era Kecerdasan Buatan bersama Universiti Brunei Darussalam', 5, 10, 'inbound', '2026-05-20', '2026-05-20', 'offline', 'Auditorium Gedung W PCU', 'ID', 174, '{4,8}', 'Seminar yang membahas dampak kecerdasan buatan terhadap rekrutmen, pengembangan talenta, dan desain pekerjaan. Menghadirkan pembicara dari UBD School of Business and Economics dan praktisi HR Surabaya, diikuti 220 peserta dari kampus dan industri.', pg_temp.wib('2026-05-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nur Amalina Haji Mohamad", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(314, 'Guest Lecture Circular Business Models dari Amsterdam Business School', 5, 15, 'inbound', '2026-09-02', '2026-09-02', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 166, '{9,12}', 'Kuliah tamu mengenai model bisnis sirkular dan contoh penerapannya pada UMKM di Belanda bagi mahasiswa mata kuliah Inovasi Model Bisnis. Sesi hybrid diikuti mahasiswa di auditorium dan peserta daring dari Amsterdam.', pg_temp.wib('2026-09-07', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maarten de Vries", "institution": "University of Amsterdam", "country_code": "NL", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(315, 'Magang Digital Business Telkom Indonesia Batch Agustus 2026', 5, 21, 'outbound', '2026-08-03', '2026-09-25', 'offline', 'Gedung Telkom Ketintang Surabaya', 'ID', 152, '{8,9}', 'Dua mahasiswa Manajemen magang delapan minggu di unit Digital Business Telkom Regional V untuk mendukung riset pasar layanan Pijar dan analisis funnel penjualan digital UMKM.', pg_temp.daysago(6, '09:00'), 'pending', pg_temp.daysago(6, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(315, '{D31239083,D31239791}', '{}', '{}');
select pg_temp.bulk_act(316, 'Studi Ekskursi Rantai Pasok Sentra UMKM Kerajinan Yogyakarta bersama UGM', 5, 24, 'outbound', '2026-09-14', '2026-09-17', 'offline', 'Fakultas Ekonomika dan Bisnis UGM', 'ID', 28, '{8,12}', 'Kunjungan studi ke sentra kerajinan perak Kotagede dan gerabah Kasongan bersama dosen FEB UGM untuk memetakan rantai pasok dan saluran distribusi UMKM. Mahasiswa mempresentasikan rekomendasi perbaikan logistik di FEB UGM.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(316, '{D31259442,D31239676,D31249971,D31259588,D31249923}', '{}', '{}');
select pg_temp.bulk_act(317, 'Indonesian Business Culture Immersion untuk Mahasiswa Chulalongkorn 2026', 5, 22, 'inbound', '2026-08-03', '2026-08-21', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,17}', 'Program imersi tiga minggu bagi mahasiswa Chulalongkorn Business School tentang budaya bisnis Indonesia, negosiasi lintas budaya, dan kunjungan ke perusahaan keluarga di Surabaya. Ditutup dengan presentasi rencana masuk pasar Indonesia.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(8, '14:00'), p_mnote => 'Transkrip nilai dan sertifikat program mahasiswa inbound belum dilampirkan pada berkas mobilitas; mohon unggah ulang beserta daftar hadir harian.', p_co_units => '{4}');
select pg_temp.bulk_pset(317, '{}', '{X05259016}', '{}');
select pg_temp.bulk_act(318, 'Pendampingan Pemasaran Digital UMKM Kampung Kue Rungkut bersama Telkom Indonesia', 5, 40, 'outbound', '2026-08-08', '2026-09-12', 'offline', 'Kampung Kue Rungkut Lor Surabaya', 'ID', 152, '{1,8,17}', 'Mahasiswa dan dosen Manajemen bersama relawan Telkom mendampingi 30 pelaku UMKM kue dalam foto produk, pemasaran WhatsApp Business, dan pembayaran QRIS. Luaran berupa peningkatan pesanan daring dan katalog bersama kampung.', pg_temp.wib('2026-09-18', '09:00'), null, null, p_ext => '[{"full_name": "Yudha Kurniawan, S.E.", "institution": "PT Telkom Indonesia (Persero) Tbk", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{4}');
select pg_temp.bulk_act(319, 'Joint Research Digital Supply Chain Resilience dengan National Taiwan University', 5, 4, 'outbound', '2026-10-15', '2027-01-29', 'hybrid', 'National Taiwan University, Taipei', 'TW', 15, '{9,17}', 'Rencana penelitian bersama tentang adopsi platform digital untuk ketahanan rantai pasok eksportir furnitur Jawa Timur ke Taiwan. Tahap awal berupa penyusunan instrumen dan pengumpulan data wawancara.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Chen Yu-ting, Ph.D.", "institution": "National Taiwan University", "country_code": "TW", "role": "researcher"}]', p_co_units => '{4}');
select pg_temp.bulk_act(320, 'Studi Ekskursi Bisnis Digital ke Telkom Indonesia Jakarta', 5, 24, 'outbound', '2026-11-17', '2026-11-20', 'offline', 'Telkom Landmark Tower Jakarta', 'ID', 168, '{8,9}', 'Rencana kunjungan studi ke program inkubasi korporat Telkom Indonesia untuk mempelajari pengembangan produk digital dan corporate venture. Peserta dari Prodi Manajemen konsentrasi Bisnis Digital.', null, null, null, p_co_units => '{4}');
select pg_temp.bulk_pset(320, '{D31249994,D31249546,D31249797,D31239469}', '{}', '{}');

select pg_temp.bulk_verify(296, 320);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_5.sql
-- seed-supabase/10_kegiatan_tambahan_5 (simks-partnership): additional bulk kegiatan 321-345, adapted from the local
-- demo seed supabase/seed/04_bulk_5.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 64, 106, 117, 150, 156, 161, 174, 175, 177, 200, 205, 206. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{64,106,117,150,156,161,174,175,177,200,205,206}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_5: SIM Kerjasama agreements missing, kegiatan 321-345 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(321, 'Student Exchange Interior Architecture di Hochschule Bremen Semester Ganjil 2025', 59, 2, 'outbound', '2025-09-08', '2025-12-26', 'offline', 'School of Architecture, Civil and Environmental Engineering, Hochschule Bremen', 'DE', 205, '{4,9,17}', 'Pertukaran pelajar satu semester mahasiswa Desain Interior di Hochschule Bremen dengan mata kuliah studio interior architecture dan desain furnitur. Kredit yang diperoleh dikonversi ke kurikulum Desain Interior PCU.', pg_temp.wib('2026-01-09', '09:00'), 'approved', pg_temp.wib('2026-01-16', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(321, '{C22239024,C22239955,C22239188}', '{}', '{}');
select pg_temp.bulk_act(322, 'Pameran dan Seminar Batik Kontemporer Motif Pesisiran Jawa Timur bersama UGM', 59, 35, 'inbound', '2025-10-02', '2025-10-03', 'offline', 'Galeri Gedung P PCU', 'ID', 117, '{4,11,12}', 'Pameran karya batik kontemporer bermotif pesisiran Jawa Timur yang diterapkan pada elemen interior, disertai seminar tentang reinterpretasi motif tradisional dalam desain tekstil modern bersama pembicara dari UGM.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Dyah Ayu Pratiwi, M.A.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker", "notes": "Departemen Sejarah dan Seni, Fakultas Ilmu Budaya UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(323, 'Kuliah Tamu Desain Interior Adaptif Iklim Tropis oleh Dosen University of Technology Sydney', 59, 15, 'inbound', '2025-10-20', '2025-10-22', 'hybrid', 'Studio Desain Interior Gedung P PCU', 'ID', 206, '{4,11,13}', 'Rangkaian kuliah tamu tiga hari tentang strategi desain interior pasif untuk iklim tropis lembap, termasuk studi kasus hunian di Australia utara dan sesi kritik studio mahasiswa.', pg_temp.wib('2025-11-05', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Sarah Whitfield", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer", "notes": "School of Design, Faculty of Design, Architecture and Building"}]', p_co_units => '{32}');
select pg_temp.bulk_act(324, 'Short Program Design Thinking for Social Innovation di KMUTT Bangkok', 59, 23, 'outbound', '2025-11-03', '2025-11-21', 'offline', 'School of Architecture and Design, KMUTT, Bangkok', 'TH', 156, '{4,10,17}', 'Program singkat tiga minggu di KMUTT yang melatih metode design thinking untuk inovasi sosial melalui proyek lapangan bersama komunitas di Bangkok. Luaran berupa prototipe ruang layanan dan presentasi akhir.', pg_temp.wib('2025-12-05', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(324, '{C22249123,C22249999,C22229438,C22249635}', '{}', '{PG452412}');
select pg_temp.bulk_act(325, 'Riset Bersama Dokumentasi Digital Wayang Kulit Jawa Timuran dengan Ateneo de Manila University', 57, 4, 'inbound', '2025-08-18', '2025-12-12', 'hybrid', 'Laboratorium Media Gedung P PCU', 'ID', 161, '{4,9,11}', 'Penelitian bersama untuk mendigitalkan koleksi wayang kulit gaya Jawa Timuran melalui fotogrametri dan pemodelan 3D, serta menyusun arsip daring yang dapat diakses peneliti di Indonesia dan Filipina.', pg_temp.wib('2026-01-12', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Maria Isabel Santos", "institution": "Ateneo de Manila University", "country_code": "PH", "role": "researcher", "notes": "Department of Communication, School of Social Sciences"}]', p_co_units => '{32}');
select pg_temp.bulk_act(326, 'Inbound Exchange Interior Architecture dari University of Technology Sydney Semester Ganjil 2025', 59, 2, 'inbound', '2025-08-25', '2025-12-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 206, '{4,17}', 'Mahasiswa pertukaran dari University of Technology Sydney mengikuti satu semester perkuliahan studio desain interior dan kelas budaya Indonesia di PCU.', pg_temp.wib('2025-12-19', '09:00'), 'approved', pg_temp.wib('2025-12-30', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(326, '{}', '{X05259022}', '{}');
select pg_temp.bulk_act(327, 'Lomba Desain Produk Furnitur Rotan PCU–UKSW 2025', 59, 35, 'inbound', '2025-11-24', '2025-11-28', 'offline', 'Auditorium Gedung W PCU', 'ID', 106, '{8,9,12}', 'Kompetisi desain furnitur berbahan rotan untuk mahasiswa desain se-Jawa yang diselenggarakan bersama UKSW, dengan penjurian prototipe dan pameran karya finalis.', pg_temp.wib('2025-12-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Yohanes Kristiawan, M.Ds.", "institution": "Universitas Kristen Satya Wacana", "country_code": "ID", "role": "other", "notes": "Juri, Program Studi Desain Komunikasi Visual UKSW"}]', p_co_units => '{32}');
select pg_temp.bulk_act(328, 'Pengabdian Masyarakat Branding dan Kemasan Batik Tulis Tanjungbumi bersama UGM', 57, 40, 'outbound', '2026-01-12', '2026-01-16', 'offline', 'Sentra Batik Tulis Tanjungbumi, Bangkalan', 'ID', 64, '{1,8,12}', 'Pendampingan perajin batik tulis Tanjungbumi dalam merancang kemasan, identitas merek, dan konten media sosial agar produk siap dipasarkan secara daring, bersama tim pengabdian Departemen Ilmu Komunikasi UGM.', pg_temp.wib('2026-02-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Novi Kurnia, M.Si.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other", "notes": "Pendamping pengabdian masyarakat, Departemen Ilmu Komunikasi Fisipol UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(329, 'Student Exchange Desain Produk dan Interior di Ateneo de Manila University Semester Genap 2026', 59, 2, 'outbound', '2026-02-02', '2026-05-29', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 161, '{4,17}', 'Mahasiswa Desain Interior menempuh satu semester di Ateneo de Manila University dengan fokus mata kuliah information design dan fine arts. Hasil studi dialihkreditkan ke kurikulum Desain Interior PCU.', pg_temp.wib('2026-06-12', '09:00'), 'approved', pg_temp.wib('2026-06-22', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(329, '{C22249514,C22239208,C22249824}', '{}', '{}');
select pg_temp.bulk_act(330, 'Credit Transfer Interior Architecture Temasek Polytechnic di PCU Semester Genap 2026', 59, 33, 'inbound', '2026-02-09', '2026-06-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 177, '{4,17}', 'Mahasiswa Temasek Polytechnic mengikuti program transfer kredit di PCU, mengambil studio desain interior, kriya kayu, dan kelas Bahasa Indonesia untuk penutur asing.', pg_temp.wib('2026-06-30', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(330, '{}', '{X05259025}', '{}');
select pg_temp.bulk_act(331, 'Pengembangan Kurikulum Bersama Desain Interior Berkelanjutan dengan Hochschule Bremen', 59, 32, 'outbound', '2026-02-16', '2026-04-24', 'online', 'Zoom Meeting', null, 205, '{4,12}', 'Serangkaian lokakarya daring untuk menyusun mata kuliah bersama tentang desain interior berkelanjutan, mencakup capaian pembelajaran, rubrik penilaian studio, dan modul material ramah lingkungan.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Lisa Hartmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "other", "notes": "Koordinator program Architecture and Interior Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(332, 'Pameran Bersama Wayang Kontemporer Indonesia–Taiwan di NTUST', 57, 35, 'outbound', '2026-03-16', '2026-03-27', 'offline', 'NTUST Design Gallery, Taipei', 'TW', 200, '{4,11,17}', 'Pameran karya dosen dan mahasiswa yang menafsirkan ulang tokoh wayang dalam media ilustrasi, video, dan instalasi, berdampingan dengan karya puppetry kontemporer mahasiswa NTUST.', pg_temp.wib('2026-04-10', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Chen Kuo-Hsiang", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "other", "notes": "Kurator pendamping, Department of Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(333, 'Studi Ekskursi Arsitektur Vernakular dan Interior Heritage ke UGM Yogyakarta', 59, 24, 'outbound', '2026-04-06', '2026-04-10', 'offline', 'Kampus UGM Bulaksumur, Yogyakarta', 'ID', 117, '{4,11}', 'Kunjungan studi mahasiswa ke Departemen Arsitektur UGM dan bangunan heritage di Yogyakarta untuk mempelajari arsitektur vernakular Jawa serta konservasi interior bangunan kolonial dan ndalem.', pg_temp.wib('2026-04-20', '09:00'), 'approved', pg_temp.wib('2026-04-28', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(333, '{C22239295,C22249177,C22229221,C22259857,C22229994,C22239024}', '{}', '{PG780858}');
select pg_temp.bulk_act(334, 'Workshop Rekayasa Bambu untuk Desain Produk bersama KMUTT', 59, 43, 'inbound', '2026-05-11', '2026-05-13', 'offline', 'Workshop Kriya Gedung P PCU', 'ID', 156, '{9,12,13}', 'Pelatihan tiga hari teknik laminasi dan pembentukan bambu untuk furnitur dan produk rumah tangga, dipandu dosen KMUTT, dengan luaran prototipe kursi lipat bambu.', pg_temp.wib('2026-05-22', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Pornchai Wongsuwan", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "visiting_lecturer", "notes": "School of Architecture and Design"}]', p_co_units => '{32}');
select pg_temp.bulk_act(335, 'Program Budaya Batik dan Wayang untuk Mahasiswa Kanazawa Institute of Technology 2026', 59, 29, 'inbound', '2026-07-06', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 175, '{4,11,17}', 'Program budaya tiga minggu bagi mahasiswa Kanazawa Institute of Technology: kelas membatik, pembuatan wayang kardus, kunjungan ke sanggar di Surabaya, dan pameran karya di akhir program.', pg_temp.wib('2026-08-05', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(335, '{}', '{X05259023}', '{}');
select pg_temp.bulk_act(336, 'Guest Lecture Speculative Product Design dari KMUTT', 59, 7, 'inbound', '2026-03-04', '2026-03-04', 'online', 'Microsoft Teams', null, 156, '{4,9}', 'Kuliah tamu daring tentang pendekatan desain spekulatif dalam pengembangan produk dan ruang masa depan, disertai diskusi proyek mahasiswa studio desain.', pg_temp.wib('2026-03-12', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nattapong Srisuk", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker", "notes": "Industrial Design Program"}]', p_co_units => '{32}');
select pg_temp.bulk_act(337, 'Creative Industries Study Tour Sydney bersama University of Technology Sydney', 57, 22, 'outbound', '2026-06-29', '2026-07-17', 'offline', 'UTS Faculty of Arts and Social Sciences, Ultimo, Sydney', 'AU', 206, '{4,11}', 'Program tiga minggu di UTS: studio produksi media dan komunikasi visual ruang publik, kunjungan ke museum dan agensi kreatif di Sydney, serta presentasi proyek kolaboratif bersama mahasiswa UTS.', pg_temp.wib('2026-07-31', '09:00'), 'approved', pg_temp.wib('2026-08-10', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(337, '{E42259904,E42249976,E42239200,E42249697,E42239001}', '{}', '{PG761401}');
select pg_temp.bulk_act(338, 'Magang Desain Interior di Design Lab KMUTT Bangkok', 59, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline', 'KMUTT Bangmod Campus, Bangkok', 'TH', 156, '{4,8}', 'Magang enam minggu di Design Lab KMUTT yang menangani proyek interior ruang belajar kampus, meliputi survei pengguna, gambar kerja, dan visualisasi 3D.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(338, '{C22249123,C22249999}', '{}', '{}');
select pg_temp.bulk_act(339, 'Inbound Short Program Kriya Nusantara untuk Mahasiswa Hochschule Bremen', 59, 23, 'inbound', '2026-08-10', '2026-08-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 205, '{4,17}', 'Program singkat tiga minggu bagi mahasiswa Hochschule Bremen untuk mempelajari kriya Nusantara (batik, anyaman, ukir kayu) melalui kelas praktik dan kunjungan ke sentra kerajinan Jawa Timur.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Transkrip nilai peserta belum diunggah dan poster kegiatan masih memakai logo lama. Mohon lengkapi bundel transkrip/poster/dokumentasi lalu ajukan ulang.', p_co_units => '{32}');
select pg_temp.bulk_pset(339, '{}', '{X06259021}', '{}');
select pg_temp.bulk_act(340, 'Riset Terapan Panel Interior dari Material Daur Ulang untuk Ruang Publik bersama Pakuwon', 59, 4, 'inbound', '2026-08-03', '2026-09-18', 'hybrid', 'Laboratorium Material Desain Gedung P PCU', 'ID', 150, '{9,11,12}', 'Penelitian terapan pengembangan panel interior dari limbah plastik dan serbuk kayu untuk area publik pusat perbelanjaan Pakuwon, termasuk uji ketahanan dan purwarupa panel akustik.', pg_temp.wib('2026-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Ir. Hendra Gunawan, M.T.", "institution": "PT Pakuwon Jati Tbk", "country_code": "ID", "role": "researcher", "notes": "Divisi Perencanaan dan Desain Interior"}]', p_co_units => '{32}');
select pg_temp.bulk_act(341, 'Kompetisi Poster Warisan Budaya Asia Tenggara bersama Universiti Brunei Darussalam', 57, 35, 'outbound', '2026-08-17', '2026-09-04', 'online', 'Zoom Meeting', null, 174, '{4,11,17}', 'Kompetisi poster daring bertema warisan budaya takbenda Asia Tenggara yang dijuri bersama dosen PCU dan Universiti Brunei Darussalam, ditutup dengan pengumuman pemenang dan pameran virtual.', pg_temp.wib('2026-09-14', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Siti Norhayati binti Haji Ahmad", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "other", "notes": "Juri, Faculty of Arts and Social Sciences"}]', p_co_units => '{32}');
select pg_temp.bulk_act(342, 'Academic Exchange Desain Pameran dan Kuratorial di Kanazawa Institute of Technology', 59, 28, 'outbound', '2026-08-24', '2026-09-18', 'offline', 'Kanazawa Institute of Technology, Nonoichi, Ishikawa', 'JP', 175, '{4,17}', 'Pertukaran akademik empat minggu untuk mempelajari desain ruang pameran dan praktik kuratorial di Kanazawa Institute of Technology, termasuk keterlibatan dalam penyiapan pameran tahunan mahasiswa.', pg_temp.daysago(4, '09:00'), 'pending', pg_temp.daysago(4, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(342, '{C22229438,C22239955,C22249635}', '{}', '{}');
select pg_temp.bulk_act(343, 'Seminar Nasional Pelestarian Interior Bangunan Kolonial Surabaya bersama UGM', 59, 10, 'inbound', '2026-09-09', '2026-09-10', 'offline', 'Auditorium Gedung W PCU', 'ID', 117, '{4,11}', 'Seminar dua hari tentang konservasi dan adaptasi interior bangunan kolonial di Surabaya, menghadirkan akademisi UGM dan praktisi cagar budaya, disertai tur lapangan ke kawasan Kota Lama.', pg_temp.wib('2026-09-21', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Ikaputra, M.Eng.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker", "notes": "Departemen Teknik Arsitektur dan Perencanaan UGM"}]', p_co_units => '{32}');
select pg_temp.bulk_act(344, 'Winter Program Craft Heritage dan Desain Kriya di NTUST 2027', 59, 23, 'outbound', '2027-01-11', '2027-01-29', 'offline', 'Department of Design, NTUST, Taipei', 'TW', 200, '{4,8,11}', 'Rencana program musim dingin di NTUST untuk mempelajari pengembangan kriya tradisional menjadi produk desain kontemporer, termasuk kunjungan ke sentra kerajinan di Taiwan.', null, null, null, p_files => '{ia}', p_co_units => '{32}');
select pg_temp.bulk_pset(344, '{C22239188,C22249514}', '{}', '{}');
select pg_temp.bulk_act(345, 'Pameran Dies Natalis Craft Heritage Batik dan Wayang bersama UKSW', 59, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline', 'Galeri Gedung P PCU', 'ID', 106, '{4,11}', 'Rencana pameran Dies Natalis yang menampilkan karya batik dan wayang kontemporer hasil kolaborasi dosen dan mahasiswa Desain Interior PCU dengan UKSW.', null, null, null, p_files => '{}', p_co_units => '{32}');

select pg_temp.bulk_verify(321, 345);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_6.sql
-- seed-supabase/10_kegiatan_tambahan_6 (simks-partnership): additional bulk kegiatan 346-370, adapted from the local
-- demo seed supabase/seed/04_bulk_6.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 156, 167, 177, 200, 204, 205, 206, 207, 208. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{156,167,177,200,204,205,206,207,208}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_6: SIM Kerjasama agreements missing, kegiatan 346-370 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(346, 'Pertukaran Pelajar Spring Session 2025 Visual Communication di University of Technology Sydney', 63, 2, 'outbound', '2025-08-04', '2025-11-21', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Tiga mahasiswa DKV mengikuti satu semester Spring Session di School of Design UTS, mengambil mata kuliah Visual Communication Studio dan Digital Media. Kredit dikonversi ke kurikulum DKV melalui skema transfer kredit.', pg_temp.wib('2025-12-03', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'));
select pg_temp.bulk_pset(346, '{C21239954,C21239549,C21239991}', '{}', '{}');
select pg_temp.bulk_act(347, 'Kuliah Tamu Motion Graphics untuk Narasi Data oleh UTS School of Design', 63, 15, 'inbound', '2025-09-17', '2025-09-17', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 206, '{4,9}', 'Kuliah tamu tentang perancangan motion graphics untuk menyampaikan data kompleks secara naratif, dilengkapi studi kasus infografis animasi media berita Australia. Diikuti mahasiswa mata kuliah Desain Animasi secara luring dan daring.', pg_temp.wib('2025-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rachel Bennett", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]', p_co_units => '{32}');
select pg_temp.bulk_act(348, 'Inbound Short Program Batik Pesisir dan Arsip Visual Kota Lama Surabaya untuk Mahasiswa Hochschule Bremen', 63, 23, 'inbound', '2025-09-08', '2025-09-26', 'offline', 'Studio DKV Gedung P PCU', 'ID', 205, '{4,11}', 'Program singkat tiga minggu bagi mahasiswa Hochschule Bremen untuk mempelajari motif batik pesisir dan arsip visual kota lama Surabaya. Luaran berupa seri ilustrasi dan pola permukaan yang dipamerkan di akhir program.', pg_temp.wib('2025-10-06', '09:00'), 'approved', pg_temp.wib('2025-10-14', '14:00'));
select pg_temp.bulk_pset(348, '{}', '{X05259028}', '{}');
select pg_temp.bulk_act(349, 'Riset Bersama Tipografi Aksara Jawa untuk Antarmuka Digital dengan Hochschule Bremen', 63, 4, 'outbound', '2025-08-18', '2025-12-12', 'hybrid', 'Lab Tipografi DKV Gedung P PCU', 'ID', 205, '{4,9}', 'Penelitian bersama untuk merancang varian font aksara Jawa yang terbaca baik pada layar ponsel. Tim menguji keterbacaan pada antarmuka aplikasi dan menyiapkan draf artikel jurnal bersama peneliti desain Hochschule Bremen.', pg_temp.wib('2026-01-20', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Jan Hoffmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "researcher"}]');
select pg_temp.bulk_act(350, 'Workshop Game Art dan Character Design bersama UTS Games Studio', 63, 35, 'inbound', '2025-10-20', '2025-10-22', 'offline', 'Lab Komputer Grafis Gedung P PCU', 'ID', 206, '{4,8}', 'Workshop tiga hari tentang pipeline game art mulai dari concept sketch, character sheet, hingga aset 2D siap pakai di game engine. Peserta menghasilkan satu karakter orisinal yang direview langsung oleh mentor UTS.', pg_temp.wib('2025-10-30', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Thomas Nguyen", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker", "notes": "Lecturer, Games Development"}]');
select pg_temp.bulk_act(351, 'Pertukaran Budaya Fotografi Dokumenter Pasar Tradisional bersama Mahasiswa Taylor''s University', 63, 29, 'inbound', '2025-11-03', '2025-11-14', 'offline', 'Kampus PCU Siwalankerto', 'ID', 167, '{4,11}', 'Mahasiswa Taylor''s University mengikuti program pertukaran budaya dengan fokus fotografi dokumenter kehidupan pasar tradisional Surabaya bersama mahasiswa DKV. Hasil foto dikurasi menjadi e-zine bersama.', pg_temp.wib('2025-11-20', '09:00'), 'approved', pg_temp.wib('2025-11-28', '14:00'));
select pg_temp.bulk_pset(351, '{}', '{X06269030}', '{}');
select pg_temp.bulk_act(352, 'Online Course UX Research Fundamentals bersama UTS', 63, 79, 'inbound', '2025-10-06', '2025-11-28', 'online', 'Zoom Meeting', null, 206, '{4,9}', 'Kursus daring delapan minggu tentang metode riset pengguna: wawancara, usability testing, dan journey mapping. Materi disampaikan dosen UTS dan dipakai sebagai pengayaan mata kuliah Desain UI/UX.', pg_temp.wib('2025-12-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Priya Raman", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(353, 'Summer Program Ilustrasi dan Picture Book di University of Technology Sydney', 63, 23, 'outbound', '2026-01-05', '2026-01-23', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Empat mahasiswa DKV mengikuti program musim panas UTS tentang ilustrasi buku cerita anak, dari pengembangan karakter hingga storyboard dan dummy book. Didampingi satu dosen DKV.', pg_temp.wib('2026-02-02', '09:00'), 'approved', pg_temp.wib('2026-02-10', '14:00'));
select pg_temp.bulk_pset(353, '{C21239626,C21239301,C21249196,C21249481}', '{}', '{}');
select pg_temp.bulk_act(354, 'Pertukaran Pelajar Autumn Session 2026 Digital Media di University of Technology Sydney', 63, 2, 'outbound', '2026-02-23', '2026-06-19', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Pertukaran satu semester bagi tiga mahasiswa DKV di program Digital and Social Media UTS, dengan mata kuliah animasi, interaction design, dan media studies. Nilai dikonversi melalui transfer kredit.', pg_temp.wib('2026-06-29', '09:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'));
select pg_temp.bulk_pset(354, '{C21239888,C21239659,C21249776}', '{}', '{}');
select pg_temp.bulk_act(355, 'Semester Pertukaran Mahasiswa UTS di Prodi DKV Genap 2025/2026', 63, 2, 'inbound', '2026-02-09', '2026-06-12', 'offline', 'Kampus PCU Siwalankerto', 'ID', 206, '{4,17}', 'Dua mahasiswa UTS mengikuti satu semester di Prodi DKV, mengambil mata kuliah Desain Komunikasi Visual Nusantara, Fotografi, dan Bahasa Indonesia untuk Penutur Asing.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-01', '14:00'));
select pg_temp.bulk_pset(355, '{}', '{X06269026,X06269027}', '{}');
select pg_temp.bulk_act(356, 'Guest Lecture Brand Identity untuk Destinasi Wisata oleh UTS', 63, 7, 'inbound', '2026-03-11', '2026-03-11', 'offline', 'Auditorium Gedung W PCU', 'ID', 206, '{8,11}', 'Kuliah umum tentang perancangan identitas merek destinasi wisata, membahas kasus rebranding kawasan kota di New South Wales dan peluang penerapannya untuk kawasan Kota Lama Surabaya.', pg_temp.wib('2026-03-18', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Sarah Mitchell", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]');
select pg_temp.bulk_act(357, 'Seminar Internasional Visualisasi Informasi dan Desain Interaksi bersama NTUST', 63, 10, 'inbound', '2026-04-15', '2026-04-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 200, '{4,9,17}', 'Seminar dua hari yang mempertemukan peneliti Fakultas Humaniora dan Industri Kreatif dengan NTUST untuk membahas visualisasi informasi, dashboard publik, dan desain interaksi. Mahasiswa DKV mempresentasikan poster karya riset.', pg_temp.wib('2026-04-24', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Chen Wei-Lun", "institution": "National Taiwan University of Science and Technology", "country_code": "TW", "role": "speaker"}]', p_co_units => '{32}');
select pg_temp.bulk_act(358, 'Pengembangan Kurikulum Peminatan Animasi 2D dan 3D bersama UTS', 63, 11, 'inbound', '2026-03-02', '2026-05-29', 'hybrid', 'Ruang Rapat Prodi DKV Gedung P PCU', 'ID', 206, '{4}', 'Penyusunan ulang capaian pembelajaran dan rencana studi peminatan animasi dengan membandingkan struktur mata kuliah animasi UTS. Luaran berupa dokumen RPS baru untuk empat mata kuliah.', pg_temp.wib('2026-06-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Hannah Brooks", "institution": "University of Technology Sydney", "country_code": "AU", "role": "other", "notes": "Program coordinator, Animation"}]');
select pg_temp.bulk_act(359, 'Pengabdian Masyarakat Rebranding UMKM Kampung Kue Rungkut bersama Pemerintah Kota Surabaya', 63, 40, 'inbound', '2026-04-20', '2026-05-15', 'offline', 'Kampung Kue Rungkut Lor, Surabaya', 'ID', 207, '{1,8,11}', 'Dosen dan mahasiswa DKV bersama Dinas Koperasi dan UMKM Pemerintah Kota Surabaya mendampingi pelaku usaha kue di Rungkut Lor merancang ulang logo, kemasan, dan konten media sosial. Sebanyak dua belas usaha menerima paket identitas visual baru.', pg_temp.wib('2026-05-25', '09:00'), null, null, p_ext => '[{"full_name": "Ibu Retno Wulandari, S.E.", "institution": "Pemerintah Kota Surabaya", "country_code": "ID", "role": "staff_visitor"}]');
select pg_temp.bulk_act(360, 'Studi Ekskursi Film Dokumenter ke Institut Teknologi Bandung', 63, 24, 'outbound', '2026-05-11', '2026-05-15', 'offline', 'Kampus ITB Ganesha, Bandung', 'ID', 208, '{4,11}', 'Mahasiswa peminatan film mengunjungi studio dan laboratorium Fakultas Seni Rupa dan Desain ITB, mengikuti kelas produksi dokumenter, serta merekam film pendek tentang ruang publik Bandung.', pg_temp.wib('2026-05-22', '09:00'), 'approved', pg_temp.wib('2026-06-02', '14:00'));
select pg_temp.bulk_pset(360, '{C21249147,C21229377,C21229391,C21239562,C21249999,C21229931}', '{}', '{}');
select pg_temp.bulk_act(361, 'Publikasi Bersama Kajian Visual Kampanye Iklim di Media Sosial dengan Temasek Polytechnic', 63, 5, 'outbound', '2026-02-02', '2026-07-17', 'online', 'Microsoft Teams', null, 177, '{13,4}', 'Kolaborasi penulisan artikel yang menganalisis strategi visual kampanye perubahan iklim di Instagram Indonesia dan Singapura bersama dosen Temasek Polytechnic School of Design. Naskah dikirim ke jurnal desain bereputasi.', pg_temp.wib('2026-08-24', '09:00'), null, null, p_ext => '[{"full_name": "Ms. Megan Tan Hui Ling", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "researcher"}]');
select pg_temp.bulk_act(362, 'Magang Desain UX/UI di Temasek Polytechnic Design School', 63, 21, 'outbound', '2026-06-29', '2026-07-31', 'offline', 'Temasek Polytechnic, Tampines, Singapore', 'SG', 177, '{8,9}', 'Tiga mahasiswa DKV magang di unit pengembangan pembelajaran digital Temasek Polytechnic, merancang prototipe antarmuka modul e-learning dan melakukan usability test bersama tim produk.', pg_temp.wib('2026-08-07', '09:00'), 'approved', pg_temp.wib('2026-08-17', '14:00'));
select pg_temp.bulk_pset(362, '{C21249451,C21239724,C21239896}', '{}', '{}');
select pg_temp.bulk_act(363, 'Short Program Desain Kemasan Berkelanjutan di KMUTT Bangkok', 63, 23, 'outbound', '2026-08-03', '2026-08-14', 'offline', 'KMUTT Bang Mod Campus, Bangkok', 'TH', 156, '{9,12}', 'Program singkat dua minggu di King Mongkut''s University of Technology Thonburi tentang desain kemasan ramah lingkungan, material alternatif, dan komunikasi visual label produk. Diikuti mahasiswa DKV dengan pendamping dari fakultas.', pg_temp.wib('2026-08-20', '09:00'), 'approved', pg_temp.wib('2026-08-31', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(363, '{C21259848,C21259343,C21259948}', '{}', '{}');
select pg_temp.bulk_act(364, 'Kuliah Tamu Sinematografi dan Color Grading dari UTS Film Studies', 63, 15, 'inbound', '2026-09-02', '2026-09-02', 'offline', 'Auditorium Gedung P PCU', 'ID', 206, '{4,8}', 'Kuliah tamu tentang bahasa visual sinematografi dan alur color grading untuk film pendek, disertai demo langsung penyuntingan warna pada footage karya mahasiswa DKV.', pg_temp.wib('2026-09-09', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Benjamin Clarke", "institution": "University of Technology Sydney", "country_code": "AU", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(365, 'Inbound Short Program Ilustrasi Cerita Rakyat Jawa Timur untuk Mahasiswa Calvin University', 63, 23, 'inbound', '2026-08-10', '2026-09-04', 'offline', 'Studio Ilustrasi Gedung P PCU', 'ID', 204, '{4,11,17}', 'Mahasiswa Calvin University mempelajari cerita rakyat Jawa Timur dan menerjemahkannya menjadi ilustrasi naratif bersama mahasiswa DKV. Karya akhir dihimpun dalam buku digital dwibahasa.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(365, '{}', '{X05259029}', '{}');
select pg_temp.bulk_act(366, 'Short Program Animasi dan Visual Effects di University of Technology Sydney', 63, 23, 'outbound', '2026-08-24', '2026-09-18', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,9}', 'Tiga mahasiswa DKV mengikuti program singkat empat minggu tentang compositing, motion tracking, dan efek visual untuk animasi pendek di studio media UTS.', pg_temp.daysago(7, '09:00'), 'pending', pg_temp.daysago(7, '09:00'));
select pg_temp.bulk_pset(366, '{C21259543,C21259428,C21259142}', '{}', '{}');
select pg_temp.bulk_act(367, 'Inbound Academic Exchange Desain Game Edukasi dari University of Technology Sydney', 63, 28, 'inbound', '2026-08-03', '2026-09-11', 'offline', 'Lab Game Art Gedung P PCU', 'ID', 206, '{4,9}', 'Dua mahasiswa UTS bergabung dengan studio game art DKV selama enam minggu untuk mengembangkan prototipe game edukasi bertema budaya Surabaya bersama mahasiswa PCU.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(6, '09:00'), p_mnote => 'Mohon unggah Letter of Acceptance untuk Hamish Clarke dan perbaiki nomor mahasiswa asal Mia Robertson sesuai transkrip UTS.');
select pg_temp.bulk_pset(367, '{}', '{X06269026,X06269027}', '{}');
select pg_temp.bulk_act(368, 'Pameran Bersama Poster Tipografi Eksperimental PCU dan Hochschule Bremen', 63, 35, 'inbound', '2026-09-14', '2026-09-19', 'hybrid', 'Galeri Gedung P PCU', 'ID', 205, '{4,11,17}', 'Pameran enam hari yang menampilkan 60 poster tipografi eksperimental karya mahasiswa DKV dan Hochschule Bremen, dilengkapi tur virtual dan diskusi kuratorial daring bersama dosen Bremen.', pg_temp.wib('2026-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Jan Hoffmann", "institution": "Hochschule Bremen", "country_code": "DE", "role": "speaker", "notes": "Kurator tamu"}]');
select pg_temp.bulk_act(369, 'Riset Bersama Visual Storytelling Edukasi Mitigasi Banjir dengan UTS', 63, 4, 'outbound', '2026-11-02', '2027-01-29', 'hybrid', 'Lab Riset DKV Gedung P PCU', 'ID', 206, '{11,13}', 'Rencana riset bersama untuk merancang komik dan animasi pendek edukasi mitigasi banjir bagi siswa sekolah dasar di Surabaya, diuji efektivitasnya bersama tim UTS.', null, null, null, p_files => '{ia}');
select pg_temp.bulk_act(370, 'Staff Exchange Dosen DKV ke UTS School of Design', 63, 3, 'outbound', '2026-11-16', '2026-11-27', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,17}', 'Dua dosen DKV direncanakan mengajar bersama di kelas Visual Communication UTS dan mempelajari tata kelola studio kreatif kampus sebagai bahan pengembangan laboratorium DKV.', null, null, null, p_ext => '[{"full_name": "Prof. Sarah Mitchell", "institution": "University of Technology Sydney", "country_code": "AU", "role": "other", "notes": "Tuan rumah program"}]');

select pg_temp.bulk_verify(346, 370);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_7.sql
-- seed-supabase/10_kegiatan_tambahan_7 (simks-partnership): additional bulk kegiatan 371-395, adapted from the local
-- demo seed supabase/seed/04_bulk_7.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 25, 30, 31, 38, 62, 100, 105, 107, 108, 112, 117, 133, 137, 156, 158, 166, 188, 190, 191, 200, 205, 206. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{25,30,31,38,62,100,105,107,108,112,117,133,137,156,158,166,188,190,191,200,205,206}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_7: SIM Kerjasama agreements missing, kegiatan 371-395 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(371, 'Program Imersi Lintas Disiplin Design Thinking & Business Innovation di Hong Kong Baptist University', 5, 22, 'outbound', '2025-08-11', '2025-08-22', 'offline', 'HKBU Kowloon Tong Campus, Hong Kong', 'HK', 62, '{4,8,9}', 'Program imersi gabungan SBM dan Fakultas Humaniora dan Industri Kreatif di Hong Kong Baptist University: mahasiswa Manajemen, Akuntansi, dan DKV bekerja dalam tim lintas disiplin merancang prototipe bisnis kreatif dengan metode design thinking, ditutup dengan pitching di depan mentor HKBU.', pg_temp.wib('2025-08-29', '09:00'), 'approved', pg_temp.wib('2025-09-05', '14:00'), p_co_units => '{4,32}');
select pg_temp.bulk_pset(371, '{D31239877,D31239764,D32249932,C21229456,C21239107}', '{}', '{PG818524}');
select pg_temp.bulk_act(372, 'Pameran Bersama Desain Produk Berkelanjutan FTI–FHIK bersama ITB', 67, 35, 'inbound', '2025-09-15', '2025-09-19', 'offline', 'Galeri Gedung P PCU', 'ID', 137, '{9,12}', 'Pameran karya bersama mahasiswa Teknik Industri, Teknik Elektro, dan program desain PCU dengan Fakultas Seni Rupa dan Desain ITB yang menampilkan 40 prototipe produk ramah lingkungan, dilengkapi sesi kurasi dan diskusi panel tentang material daur ulang.', pg_temp.wib('2025-09-25', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Andar Bagus Sriwarno, M.Ds.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "speaker"}, {"full_name": "Prof. Dr. Imam Santosa, M.Sn.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "speaker"}]', p_co_units => '{28,32,65}');
select pg_temp.bulk_act(373, 'International Conference on Applied Computing, Embedded Systems and Smart Manufacturing (ICACES) 2025 bersama Temasek Polytechnic', 67, 10, 'inbound', '2025-10-08', '2025-10-09', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 188, '{4,9,17}', 'Konferensi internasional yang diselenggarakan Prodi Teknik Industri bersama FTI, Prodi Informatika, Teknik Elektro, dan Kantor Kerja Sama dan Urusan Internasional dengan Temasek Polytechnic; menghadirkan 62 makalah tentang sistem tertanam, IoT, dan manufaktur cerdas serta keynote dari School of Engineering TP.', pg_temp.wib('2025-10-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Lim Wei Sheng", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "speaker"}, {"full_name": "Ms. Tan Hui Min", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "speaker"}]', p_co_units => '{28,68,65,2}');
select pg_temp.bulk_act(374, 'Student Exchange Semester Ganjil Informatika dan DKV di NTUST Taipei', 68, 2, 'outbound', '2025-09-01', '2026-01-16', 'offline', 'NTUST Gongguan Campus, Taipei', 'TW', 200, '{4,9}', 'Pertukaran satu semester bagi mahasiswa Informatika dan DKV di National Taiwan University of Science and Technology; peserta mengambil mata kuliah Human-Computer Interaction dan Interactive Media Design yang diakui melalui transfer kredit.', pg_temp.wib('2026-01-26', '09:00'), 'approved', pg_temp.wib('2026-02-04', '14:00'), p_co_units => '{28,32,63}');
select pg_temp.bulk_pset(374, '{B11229965,B11239432,C21249850}', '{}', '{}');
select pg_temp.bulk_act(375, 'Inbound Academic Exchange Kanazawa Institute of Technology di Laboratorium Sistem Kontrol', 65, 28, 'inbound', '2025-10-01', '2025-12-19', 'offline', 'Laboratorium Sistem Kontrol Gedung P PCU', 'ID', 105, '{4,9}', 'Mahasiswa Kanazawa Institute of Technology mengikuti pertukaran akademik di Prodi Teknik Elektro dengan pembimbingan bersama dosen Teknik Elektro dan Informatika, mengerjakan proyek sistem kontrol robot pemindah barang berbasis visi komputer.', pg_temp.wib('2025-12-29', '09:00'), 'approved', pg_temp.wib('2026-01-08', '14:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(375, '{}', '{X05269034}', '{PG413450}');
select pg_temp.bulk_act(376, 'Kuliah Bersama Brand Strategy & Visual Identity dengan University of Amsterdam', 5, 34, 'inbound', '2025-11-04', '2025-11-25', 'online', 'Zoom Meeting', null, 166, '{4,8}', 'Empat sesi kuliah bersama daring antara SBM, Prodi Manajemen, dan Prodi DKV dengan Amsterdam Business School, University of Amsterdam, tentang strategi merek dan identitas visual; mahasiswa lintas prodi menyusun brand audit untuk UMKM Surabaya.', pg_temp.wib('2025-12-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Femke van Horen", "institution": "University of Amsterdam", "country_code": "NL", "role": "visiting_lecturer"}]', p_co_units => '{4,63}');
select pg_temp.bulk_act(377, 'Batik dan Desain Nusantara: Program Budaya Mahasiswa Hochschule Bremen', 63, 29, 'inbound', '2025-11-10', '2025-11-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 205, '{4,11}', 'Program pertukaran budaya tiga minggu untuk mahasiswa Hochschule Bremen yang dikelola Prodi DKV, Fakultas Humaniora dan Industri Kreatif, serta Kantor Kerja Sama dan Urusan Internasional: lokakarya batik, kunjungan sentra kriya Madura, dan proyek desain motif kontemporer bersama mahasiswa DKV.', pg_temp.wib('2025-12-05', '09:00'), 'approved', pg_temp.wib('2025-12-12', '14:00'), p_co_units => '{32,2}');
select pg_temp.bulk_pset(377, '{}', '{X05269035}', '{PG780858}');
select pg_temp.bulk_act(378, 'Service Learning Digitalisasi UMKM Kampung Lontong bersama Universitas Pelita Harapan', 6, 40, 'outbound', '2025-12-01', '2025-12-12', 'offline', 'Kampung Lontong Banyu Urip, Surabaya', 'ID', 112, '{1,8,17}', 'Pengabdian masyarakat Prodi Akuntansi bersama SBM, Prodi Manajemen, dan Prodi Informatika dengan Universitas Pelita Harapan: pendampingan pencatatan keuangan sederhana, katalog digital, dan pembayaran QRIS bagi 25 pelaku UMKM lontong.', pg_temp.wib('2025-12-18', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rahmat Setiawan, S.E., M.M.", "institution": "Universitas Pelita Harapan", "country_code": "ID", "role": "other"}]', p_co_units => '{4,5,68}');
select pg_temp.bulk_act(379, 'Winter Short Program Smart Factory & Electrical Engineering di Kanazawa Institute of Technology', 65, 23, 'outbound', '2026-02-02', '2026-02-20', 'offline', 'Kanazawa Institute of Technology, Ogigaoka Campus', 'JP', 105, '{4,7,9}', 'Program singkat tiga minggu bagi mahasiswa Teknik Elektro dan Informatika di Kanazawa Institute of Technology: kuliah otomasi pabrik, praktikum PLC dan sensor, serta kunjungan ke fasilitas manufaktur di wilayah Hokuriku.', pg_temp.wib('2026-03-02', '09:00'), 'approved', pg_temp.wib('2026-03-10', '14:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(379, '{B12239310,B12249808,B12259428,B11229081}', '{}', '{PG204517}');
select pg_temp.bulk_act(380, 'Inbound Student Exchange National Taiwan University Genap 2026 di Prodi Manajemen', 5, 2, 'inbound', '2026-02-09', '2026-06-26', 'offline', 'Gedung T PCU', 'ID', 30, '{4,17}', 'Mahasiswa National Taiwan University mengikuti satu semester di Prodi Manajemen dengan mata kuliah pilihan dari SBM (Pemasaran Digital, Kewirausahaan Asia Tenggara) dan didampingi buddy mahasiswa Manajemen.', pg_temp.wib('2026-07-06', '09:00'), 'approved', pg_temp.wib('2026-07-15', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(380, '{}', '{X06269031}', '{PG295222}');
select pg_temp.bulk_act(381, 'Inbound Study Abroad Monash: International Business in Southeast Asia', 5, 20, 'inbound', '2026-02-16', '2026-06-12', 'offline', 'Gedung T PCU', 'ID', 108, '{4,8,17}', 'Program study abroad satu semester untuk mahasiswa Monash University yang dikelola Prodi Manajemen, SBM, dan Kantor Kerja Sama dan Urusan Internasional; mencakup modul bisnis internasional Asia Tenggara, kunjungan industri Surabaya, dan proyek konsultasi bersama mahasiswa lokal.', pg_temp.wib('2026-06-22', '09:00'), 'approved', pg_temp.wib('2026-07-01', '14:00'), p_co_units => '{4,2}');
select pg_temp.bulk_pset(381, '{}', '{X06259033}', '{PG974721}');
select pg_temp.bulk_act(382, 'Petra–KMUTT International Week 2026: Sustainable Business and Creative Economy', 63, 10, 'inbound', '2026-03-09', '2026-03-13', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 156, '{8,12,17}', 'Pekan internasional tingkat universitas yang diselenggarakan Prodi DKV, Fakultas Humaniora dan Industri Kreatif, SBM, Kantor Kerja Sama dan Urusan Internasional, dan Rektorat bersama KMUTT: seminar ekonomi kreatif, lokakarya kemasan berkelanjutan, dan pameran startup mahasiswa kedua kampus.', pg_temp.wib('2026-03-20', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Suthep Wongsawat", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}, {"full_name": "Dr. Pimchanok Rattanakul", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]', p_co_units => '{32,4,2,1}');
select pg_temp.bulk_act(383, 'Riset Bersama Antarmuka Augmented Reality untuk Museum dengan University of Amsterdam', 68, 4, 'inbound', '2026-02-02', '2026-06-30', 'hybrid', 'Laboratorium Multimedia Gedung P PCU', 'ID', 191, '{9,11}', 'Penelitian bersama Prodi Informatika, Fakultas Humaniora dan Industri Kreatif, dan Prodi DKV dengan University of Amsterdam untuk merancang antarmuka AR pemandu koleksi Museum House of Sampoerna; luaran berupa prototipe aplikasi, uji pengguna dengan 60 pengunjung, dan draf artikel jurnal.', pg_temp.wib('2026-08-05', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Julia Noordegraaf", "institution": "University of Amsterdam", "country_code": "NL", "role": "researcher"}]', p_co_units => '{28,32,63}');
select pg_temp.bulk_act(384, 'Magang Industri Kreatif dan Teknologi di Pusat Inovasi Temasek Polytechnic', 68, 21, 'outbound', '2026-06-01', '2026-07-24', 'offline', 'Temasek Polytechnic, Tampines Campus', 'SG', 188, '{4,8}', 'Magang delapan minggu bagi mahasiswa Informatika dan DKV di pusat inovasi Temasek Polytechnic, mengerjakan proyek aplikasi interaktif untuk klien industri di bawah supervisi bersama FTI dan Prodi DKV.', pg_temp.wib('2026-08-03', '09:00'), 'approved', pg_temp.wib('2026-08-12', '14:00'), p_co_units => '{28,63}');
select pg_temp.bulk_pset(384, '{B11259395,B11249182,C21249850}', '{}', '{PG564518}');
select pg_temp.bulk_act(385, 'Pengembangan Kurikulum Bersama Minor Technopreneurship FTI–SBM dengan UTM', 67, 11, 'inbound', '2026-04-06', '2026-04-08', 'online', 'Microsoft Teams', null, 107, '{4,8,9}', 'Lokakarya daring tiga hari antara Prodi Teknik Industri, FTI, SBM, dan Prodi Manajemen dengan Universiti Teknologi Malaysia untuk menyusun capaian pembelajaran dan struktur 20 SKS minor technopreneurship lintas fakultas.', pg_temp.wib('2026-04-15', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Nor Haslinda Ismail", "institution": "Universiti Teknologi Malaysia", "country_code": "MY", "role": "other"}]', p_co_units => '{28,4,5}');
select pg_temp.bulk_act(386, 'Workshop Bersama Desain Interior dan Rekayasa Material Bambu di UGM', 59, 35, 'outbound', '2026-05-11', '2026-05-13', 'offline', 'Kampus UGM Bulaksumur, Yogyakarta', 'ID', 117, '{9,12}', 'Lokakarya tiga hari dosen Desain Interior, DKV, dan FTI bersama Departemen Teknik Mesin dan Industri UGM tentang pemanfaatan limbah tekstil dan bambu sebagai material interior, menghasilkan rencana proyek bersama 2026/2027.', pg_temp.wib('2026-05-20', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Ratna Kusumawardani, M.T.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]', p_co_units => '{32,63,28}');
select pg_temp.bulk_act(387, 'Pelatihan Akuntansi Digital dan Analitik Bisnis bersama Universitas Surabaya', 6, 43, 'outbound', '2026-07-13', '2026-07-17', 'offline', 'Fakultas Bisnis dan Ekonomika Ubaya, Kampus Tenggilis Surabaya', 'ID', 158, '{4,8}', 'Pelatihan lima hari bagi dosen dan asisten Prodi Akuntansi, SBM, dan Prodi Manajemen di Fakultas Bisnis dan Ekonomika Universitas Surabaya tentang otomasi akuntansi berbasis cloud dan dashboard analitik bisnis, ditutup dengan sertifikasi internal.', pg_temp.wib('2026-07-27', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Yie Ke Feliana, S.E., M.Comm., Ak.", "institution": "Universitas Surabaya", "country_code": "ID", "role": "speaker"}]', p_co_units => '{4,5}');
select pg_temp.bulk_act(388, 'Yonsei International Summer School 2026 Business and Culture Track', 5, 23, 'outbound', '2026-08-03', '2026-08-21', 'offline', 'Yonsei University Sinchon Campus, Seoul', 'KR', 31, '{4,8,17}', 'Summer school internasional yang dikoordinasikan Kantor Kerja Sama dan Urusan Internasional bersama SBM dan Prodi Manajemen; mahasiswa Manajemen dan Akuntansi mengikuti modul Korean business culture dan corporate visit ke Seoul.', pg_temp.wib('2026-08-28', '09:00'), 'approved', pg_temp.wib('2026-09-07', '14:00'), p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(388, '{D31249852,D31229441,D32239280,D32239903}', '{}', '{PG214411}');
select pg_temp.bulk_act(389, 'Inbound Summer Program Chulalongkorn University: Akuntansi dan Bisnis Digital Indonesia', 5, 23, 'inbound', '2026-08-03', '2026-08-28', 'offline', 'Gedung T PCU', 'ID', 25, '{4,8}', 'Program singkat empat minggu untuk mahasiswa Chulalongkorn University yang diselenggarakan Prodi Manajemen, Prodi Akuntansi, SBM, dan Kantor Kerja Sama dan Urusan Internasional: kuliah akuntansi dan ekosistem bisnis digital Indonesia serta kunjungan ke startup Surabaya.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(389, '{}', '{X05269032}', '{PG637448}');
select pg_temp.bulk_act(390, 'Short Course Teknologi Energi Terbarukan dan IoT di Universiti Teknologi Malaysia', 65, 22, 'outbound', '2026-08-24', '2026-09-04', 'offline', 'Universiti Teknologi Malaysia, Johor Bahru', 'MY', 107, '{4,7,13}', 'Program imersi dua minggu bagi mahasiswa Teknik Elektro dan Informatika di UTM tentang sistem panel surya, manajemen energi berbasis IoT, dan kunjungan ke pembangkit tenaga surya di Johor.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{28,68}');
select pg_temp.bulk_pset(390, '{B12239310,B12239803,B11229081}', '{}', '{PG703063}');
select pg_temp.bulk_act(391, 'Pertukaran Budaya Desain dan Bisnis Kreatif di Ateneo de Manila University', 63, 29, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 133, '{4,8,11}', 'Pertukaran budaya dua minggu mahasiswa DKV, Manajemen, dan Akuntansi di Ateneo de Manila University dengan lokakarya ekonomi kreatif Filipina, kunjungan komunitas seniman Intramuros, dan presentasi proyek kolaboratif.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Sertifikat partisipasi dari Ateneo de Manila University untuk D31249140 dan D32249413 belum ada di bundel mobilitas, dan dosen pendamping belum dicantumkan; mohon lengkapi lalu ajukan ulang.', p_co_units => '{32,4}');
select pg_temp.bulk_pset(391, '{C21229874,C21239176,D31249140,D32249413}', '{}', '{}');
select pg_temp.bulk_act(392, 'Kuliah Tamu Internet of Things untuk Smart Building dari Chulalongkorn University', 65, 15, 'inbound', '2026-09-08', '2026-09-08', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 38, '{7,9,11}', 'Kuliah tamu gabungan Prodi Teknik Elektro, FTI, dan Prodi Informatika tentang integrasi IoT dan sistem manajemen energi gedung, dihadiri 180 mahasiswa luring dan daring.', pg_temp.wib('2026-09-14', '09:00'), null, null, p_ext => '[{"full_name": "Asst. Prof. Dr. Kittipong Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]', p_co_units => '{28,68}');
select pg_temp.bulk_act(393, 'Kunjungan Akademik Pimpinan Universitas ke Kanazawa Institute of Technology untuk Penjajakan Joint Lab', 69, 27, 'outbound', '2026-09-14', '2026-09-17', 'offline', 'Kanazawa Institute of Technology, Yatsukaho Campus', 'JP', 190, '{9,17}', 'Kunjungan delegasi Prodi Teknik Mesin dan FTI bersama Rektorat serta Kantor Kerja Sama dan Urusan Internasional ke Kanazawa Institute of Technology untuk meninjau fasilitas riset material komposit dan robotika serta menyepakati rencana joint laboratory.', pg_temp.wib('2026-09-24', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Takahiro Nakamura", "institution": "Kanazawa Institute of Technology", "country_code": "JP", "role": "other"}]', p_co_units => '{28,1,2}');
select pg_temp.bulk_act(394, 'Joint Exhibition Petra–UTS Visual Storytelling 2026', 63, 35, 'inbound', '2026-11-16', '2026-11-20', 'offline', 'Galeri Gedung P PCU', 'ID', 206, '{4,11}', 'Rencana pameran bersama karya visual storytelling mahasiswa DKV PCU dan University of Technology Sydney, didukung Kantor Kerja Sama dan Urusan Internasional, dengan sesi artist talk dan lokakarya komik digital.', null, null, null, p_files => '{ia}', p_co_units => '{32,2}');
select pg_temp.bulk_act(395, 'Fontys Winter School International Marketing 2027', 5, 23, 'outbound', '2027-01-11', '2027-01-22', 'offline', 'Fontys University of Applied Sciences, Eindhoven', 'NL', 100, '{4,8}', 'Rencana winter school dua minggu di Fontys bagi mahasiswa Manajemen dan Akuntansi yang dikoordinasikan SBM dan Kantor Kerja Sama dan Urusan Internasional, berfokus pada pemasaran internasional dan riset pasar Eropa.', null, null, null, p_co_units => '{4,6,2}');
select pg_temp.bulk_pset(395, '{D31239877,D32249932}', '{}', '{}');

select pg_temp.bulk_verify(371, 395);

-- >>> supabase/seed-supabase/10_kegiatan_tambahan_8.sql
-- seed-supabase/10_kegiatan_tambahan_8 (simks-partnership): additional bulk kegiatan 396-420, adapted from the local
-- demo seed supabase/seed/04_bulk_8.sql to the real SIM Kerjasama units (Program Studi submitters) and agreements.
-- Generated from a reviewed JSON list; every row passes the guards below (agreement valid for the dates, submission
-- after the end date, Mobility decision after the submission, participant set for every submitted mobility kegiatan,
-- no student in two overlapping kegiatan, unique names). Needs 03_accounts.sql and 09_registries_tambahan.sql.
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.*; SIM Kerjasama tables are only read.

-- The kegiatan reference SIM Kerjasama agreements 11, 19, 25, 28, 30, 31, 42, 72, 105, 107, 126, 133, 151, 156, 158, 166, 174, 188, 191, 195, 205, 206, 208. Where any is missing (e.g. the local
-- --rehearse fixture, which only mirrors agreements 11-52) the whole file is skipped with a notice instead of failing.
drop table if exists pg_temp.tambahan_skip;
create temp table tambahan_skip as
select exists (select 1 from unnest('{11,19,25,28,30,31,42,72,105,107,126,133,151,156,158,166,174,188,191,195,205,206,208}'::int[]) d where not exists (select 1 from kerjasama.documents k where k.id = d)) as skip;
do $$ begin if (select skip from pg_temp.tambahan_skip) then
  raise notice '10_kegiatan_tambahan_8: SIM Kerjasama agreements missing, kegiatan 396-420 skipped'; end if; end $$;


create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;

create or replace function pg_temp.blob(p_path text, p_by uuid, p_at timestamptz) returns void language sql as $$
  insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
  values (p_path, split_part(p_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), p_by, p_at)
  on conflict (path) do nothing $$;

create or replace function pg_temp.log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, false, p_at) $$;

-- One kegiatan. p_submitted null = draft. Mobility agendas need p_mstatus ('approved' | 'pending' | 'revision_requested')
-- once submitted (+ p_msince for approved / revision_requested); non-mobility agendas take p_mstatus null.
create or replace function pg_temp.bulk_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[] default '{ia,ir}', p_mnote text default null, p_ext jsonb default '[]', p_co_units int[] default '{}')
returns void language plpgsql as $$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n); v_code text;
        v_creator uuid; v_created timestamptz; k text; v_path text; e jsonb; v_mob boolean; u int;
        c_mob uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  -- guards
  if p_n not between 221 and 420 then raise exception 'bulk %: number outside 221..420', p_n; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then raise exception 'bulk %: unit % is not a Program Studi', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'bulk %: agenda % missing', p_n, p_agenda; end if;
  if exists (select 1 from realisasi.activities where lower(name) = lower(p_name)) then
    raise exception 'bulk %: duplicate kegiatan name "%"', p_n, p_name; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'bulk %: document % not valid for % .. %', p_n, p_doc, p_start, p_end; end if;
  if p_country is not null and not exists (select 1 from kerjasama.countries where code = p_country) then
    raise exception 'bulk %: country % missing', p_n, p_country; end if;
  if p_country is null and p_mode <> 'online' then raise exception 'bulk %: country required unless online', p_n; end if;
  if cardinality(p_sdgs) = 0 or exists (select 1 from unnest(p_sdgs) s where s not between 1 and 17) then
    raise exception 'bulk %: 1..17 SDGs required', p_n; end if;
  if coalesce(length(p_desc), 0) < 40 then raise exception 'bulk %: description too short', p_n; end if;
  v_mob := realisasi.agenda_is_mobility(p_agenda);
  if p_submitted is not null then
    if (p_submitted at time zone 'Asia/Jakarta')::date <= p_end then raise exception 'bulk %: submitted on/before end date', p_n; end if;
    if (p_submitted at time zone 'Asia/Jakarta')::date > realisasi.today() then raise exception 'bulk %: submitted in the future', p_n; end if;
    if v_mob and coalesce(p_mstatus, '') not in ('approved', 'pending', 'revision_requested') then
      raise exception 'bulk %: mobility kegiatan needs p_mstatus approved/pending/revision_requested', p_n; end if;
    if not v_mob and p_mstatus is not null then raise exception 'bulk %: non-mobility kegiatan takes p_mstatus null', p_n; end if;
    if p_mstatus in ('approved', 'revision_requested') and (p_msince is null or p_msince <= p_submitted) then
      raise exception 'bulk %: p_msince must follow p_submitted', p_n; end if;
    if p_mstatus = 'revision_requested' and p_mnote is null then raise exception 'bulk %: revision needs p_mnote', p_n; end if;
    if not p_files @> '{ia,ir}' then raise exception 'bulk %: a submitted kegiatan needs IA and IR', p_n; end if;
  end if;

  -- creator as in 06/07: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) for the prodi
  v_creator := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
  v_created := coalesce(p_submitted, pg_temp.wib(p_end)) - interval '3 days';
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 when p_end - p_start >= 14 then 6 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created);
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  foreach u in array p_co_units loop
    if u = p_unit or not exists (select 1 from kerjasama.units where id = u) then raise exception 'bulk %: bad co-unit %', p_n, u; end if;
    insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, u, false);
  end loop;
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select distinct v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    perform pg_temp.blob(v_path, v_creator, v_created + interval '1 day');
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  perform pg_temp.log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if v_mob and p_mstatus = 'approved' then perform pg_temp.log(p_n, 'verification', 'mobility', 'approve', c_mob, p_msince, null, '{"version":1}'); end if;
  if v_mob and p_mstatus = 'revision_requested' then perform pg_temp.log(p_n, 'verification', 'mobility', 'request_revision', c_mob, p_msince, p_mnote); end if;
end $$;

-- Participant set v1 of a mobility kegiatan; status follows the activity's Mobility track (draft for a draft kegiatan).
create or replace function pg_temp.bulk_pset(p_n int, p_internal text[], p_inbound text[] default '{}', p_staff text[] default '{}')
returns void language plpgsql as $$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; a realisasi.activities; v_bad text;
        v_status text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select * into a from realisasi.activities where id = v_act;
  if a.id is null then raise exception 'bulk_pset %: activity missing', p_n; end if;
  if not realisasi.agenda_is_mobility(a.agenda_id) then raise exception 'bulk_pset %: only mobility kegiatan carry participants', p_n; end if;
  if cardinality(p_internal) + cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: no students', p_n; end if;
  if a.direction = 'outbound' and cardinality(p_internal) = 0 then raise exception 'bulk_pset %: outbound needs internal students', p_n; end if;
  if a.direction = 'inbound' and cardinality(p_inbound) = 0 then raise exception 'bulk_pset %: inbound needs inbound students', p_n; end if;
  select string_agg(x, ',') into v_bad from unnest(p_internal) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'regular' and s.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active regular students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_inbound) x
   where not exists (select 1 from mock_baak.students s where s.nrp = x and s.category = 'inbound_exchange');
  if v_bad is not null then raise exception 'bulk_pset %: not inbound students: %', p_n, v_bad; end if;
  select string_agg(x, ',') into v_bad from unnest(p_staff) x
   where not exists (select 1 from mock_hr.employees e where e.employee_id = x and e.status = 'active');
  if v_bad is not null then raise exception 'bulk_pset %: not active employees: %', p_n, v_bad; end if;
  select string_agg(distinct ps.nrp || ' (' || o.code || ')', ', ') into v_bad
    from realisasi.participant_students ps
    join realisasi.participant_set_versions v on v.id = ps.set_version_id and v.status <> 'superseded'
    join realisasi.activities o on o.id = v.activity_id and o.id <> v_act
   where ps.nrp = any (p_internal || p_inbound) and o.start_date <= a.end_date and a.start_date <= o.end_date;
  if v_bad is not null then raise exception 'bulk_pset %: students already in an overlapping kegiatan: %', p_n, v_bad; end if;

  v_status := case when a.submitted_at is null then 'draft' else a.mobility_status::text end;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at, review_note)
  values (v_id, v_act, 1, v_status::realisasi.pset_status, a.created_by, a.submitted_at,
          case when v_status in ('approved', 'revision_requested') then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end,
          case when v_status in ('approved', 'revision_requested') then a.mobility_since end,
          case when v_status = 'revision_requested'
               then (select note from realisasi.activity_log where activity_id = v_act and action = 'request_revision' limit 1) end);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution,
         'HS-' || right(s.nrp, 4), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
end $$;

-- End-of-file check for one bulk file: exactly the expected rows exist and every submitted mobility kegiatan has its
-- participant set.
create or replace function pg_temp.bulk_verify(p_from int, p_to int) returns void language plpgsql as $$
declare v_n int; v_bad text;
begin
  if (select skip from pg_temp.tambahan_skip) then return; end if;
  select count(*) into v_n from realisasi.activities a where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g);
  if v_n <> p_to - p_from + 1 then raise exception 'bulk_verify %..%: % of % kegiatan present', p_from, p_to, v_n, p_to - p_from + 1; end if;
  select string_agg(a.code, ', ') into v_bad from realisasi.activities a
   where a.id = any (select pg_temp.aid(g) from generate_series(p_from, p_to) g)
     and realisasi.agenda_is_mobility(a.agenda_id) and a.submitted_at is not null
     and not exists (select 1 from realisasi.participant_set_versions v where v.activity_id = a.id);
  if v_bad is not null then raise exception 'bulk_verify: mobility kegiatan without participants: %', v_bad; end if;
  perform setval('realisasi.activity_code_seq', greatest(420, (select last_value from realisasi.activity_code_seq)));
end $$;

select pg_temp.bulk_act(396, 'Riset Bersama Sensor Getaran Struktur Jembatan dengan Universitas Gadjah Mada', 65, 4, 'outbound', '2025-10-20', '2026-01-30', 'offline', 'Laboratorium Struktur, Fakultas Teknik UGM, Yogyakarta', 'ID', 28, '{9,11}', 'Riset bersama pengembangan sensor getaran berbasis MEMS untuk pemantauan kesehatan struktur jembatan. Tim Teknik Elektro melakukan kalibrasi prototipe di laboratorium struktur UGM dan menyusun draf artikel bersama sebelum perjanjian kerja sama tersebut diarsipkan.', pg_temp.wib('2026-02-12', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr. Ir. Bambang Suhendro, M.Sc.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "researcher"}]', p_co_units => '{28}');
select pg_temp.bulk_act(397, 'Kuliah Tamu Lean Production 4.0 dari Technische Hochschule Deggendorf', 67, 7, 'inbound', '2025-11-12', '2025-11-12', 'offline', 'Auditorium Gedung P PCU', 'ID', 126, '{8,9}', 'Kuliah tamu tentang penerapan lean production yang terintegrasi dengan sensor IoT di industri manufaktur Bavaria, diikuti mahasiswa Teknik Industri dan Informatika.', pg_temp.wib('2025-11-20', '09:00'), null, null, p_ext => '[{"full_name": "Prof. Dr.-Ing. Markus Hofbauer", "institution": "Technische Hochschule Deggendorf", "country_code": "DE", "role": "speaker"}]', p_co_units => '{28,68}');
select pg_temp.bulk_act(398, 'Short Program Power Electronics di Hochschule Bremen', 65, 23, 'outbound', '2025-10-13', '2025-10-31', 'offline', 'Hochschule Bremen, Campus Neustadtswall', 'DE', 195, '{4,7}', 'Program singkat tiga minggu tentang desain konverter daya dan inverter untuk sistem energi terbarukan. Mahasiswa Teknik Elektro mengikuti kuliah, praktikum laboratorium, dan kunjungan ke industri turbin angin di Bremerhaven.', pg_temp.wib('2026-01-20', '09:00'), 'approved', pg_temp.wib('2026-01-29', '14:00'));
select pg_temp.bulk_pset(398, '{B12239276,B12239596}', '{}', '{PG204517}');
select pg_temp.bulk_act(399, 'Kuliah Tamu Daring Motion Graphics untuk Kampanye Sosial bersama University of Technology Sydney', 63, 7, 'inbound', '2025-12-03', '2025-12-03', 'online', 'Zoom Meeting', null, 206, '{4,17}', 'Kuliah tamu daring tentang perancangan motion graphics untuk kampanye kesadaran sosial, termasuk studi kasus kampanye kesehatan publik di New South Wales dan sesi tanya jawab portofolio.', pg_temp.wib('2025-12-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Emma Fitzgerald", "institution": "University of Technology Sydney", "country_code": "AU", "role": "speaker"}]');
select pg_temp.bulk_act(400, 'Inbound Exchange University of Amsterdam di Prodi Manajemen Semester Ganjil 2025/2026', 5, 2, 'inbound', '2025-09-01', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 166, '{4,17}', 'Mahasiswa pertukaran dari University of Amsterdam mengikuti satu semester perkuliahan reguler Manajemen, termasuk mata kuliah Bisnis Internasional dan kelas Bahasa Indonesia untuk penutur asing.', pg_temp.wib('2026-01-26', '09:00'), 'approved', pg_temp.wib('2026-02-04', '14:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(400, '{}', '{X06269040}', '{PG818524}');
select pg_temp.bulk_act(401, 'Joint Webinar Manajemen Operasi Rantai Halal Asia Tenggara bersama KMUTT', 5, 10, 'inbound', '2025-11-25', '2025-11-25', 'hybrid', 'Ruang Seminar Gedung T PCU', 'ID', 156, '{8,12}', 'Webinar hibrida yang membahas tantangan sertifikasi dan logistik produk halal di Thailand dan Indonesia, dengan pembicara dari KMUTT dan dosen Manajemen PCU.', pg_temp.wib('2025-12-02', '09:00'), null, null, p_ext => '[{"full_name": "Assoc. Prof. Dr. Somchai Prasertsri", "institution": "King Mongkut''s University of Technology Thonburi", "country_code": "TH", "role": "speaker"}]');
select pg_temp.bulk_act(402, 'Staff Exchange Laboratorium Mekatronika ke Universitas Gadjah Mada', 65, 3, 'outbound', '2026-05-11', '2026-05-22', 'offline', 'Departemen Teknik Elektro dan Teknologi Informasi, Fakultas Teknik UGM, Yogyakarta', 'ID', 72, '{4,9}', 'Dua dosen Teknik Elektro menjalani program pertukaran staf di laboratorium mekatronika UGM untuk mempelajari tata kelola laboratorium riset dan merancang praktikum bersama di bawah perjanjian yang masih berlaku.', pg_temp.wib('2026-06-03', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Ir. Adha Imam Cahyadi, M.Eng.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor"}]', p_co_units => '{28}');
select pg_temp.bulk_act(403, 'Program Budaya Seni Tradisi Jawa untuk Mahasiswa Yonsei University', 63, 29, 'inbound', '2026-02-09', '2026-03-20', 'offline', 'Studio Desain Gedung P PCU', 'ID', 31, '{4,11}', 'Mahasiswa Yonsei University mengikuti program enam minggu tentang batik, wayang, dan ragam hias Jawa Timur, ditutup dengan pameran karya kolaboratif bersama mahasiswa Desain Komunikasi Visual.', pg_temp.wib('2026-05-04', '09:00'), 'approved', pg_temp.wib('2026-05-12', '14:00'), p_co_units => '{32}');
select pg_temp.bulk_pset(403, '{}', '{X05269037}', '{PG761401}');
select pg_temp.bulk_act(404, 'Online Course Cloud Native Development dari Temasek Polytechnic', 68, 79, 'inbound', '2026-03-02', '2026-04-24', 'online', 'Microsoft Teams', null, 188, '{4,9}', 'Kursus daring delapan minggu tentang container, Kubernetes, dan CI/CD yang diampu dosen Temasek Polytechnic untuk mahasiswa Informatika, dengan proyek akhir deployment aplikasi mikroservis.', pg_temp.wib('2026-05-06', '09:00'), null, null, p_ext => '[{"full_name": "Mr. Lim Wei Jie", "institution": "Temasek Polytechnic", "country_code": "SG", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(405, 'Pameran Bersama Tipografi Nusantara bersama ITB', 63, 35, 'outbound', '2026-04-20', '2026-04-25', 'offline', 'Galeri Soemardja, Institut Teknologi Bandung', 'ID', 208, '{4,11}', 'Pameran karya tipografi berbasis aksara daerah hasil kolaborasi mahasiswa DKV PCU dan FSRD ITB, disertai diskusi kuratorial tentang digitalisasi aksara Nusantara.', pg_temp.wib('2026-05-02', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Andi Wiranata, M.Sn.", "institution": "Institut Teknologi Bandung", "country_code": "ID", "role": "other"}]');
select pg_temp.bulk_act(406, 'Pengabdian Masyarakat Pembukuan Digital UMKM Kampung Lawas Maspati bersama Universitas Surabaya', 6, 40, 'outbound', '2026-06-15', '2026-06-19', 'offline', 'Kampung Lawas Maspati, Surabaya', 'ID', 158, '{1,8}', 'Dosen dan mahasiswa Akuntansi bersama tim Universitas Surabaya mendampingi pelaku UMKM kampung wisata dalam pencatatan keuangan sederhana menggunakan aplikasi kasir digital.', pg_temp.wib('2026-08-10', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Rahmawati Santoso, S.E., M.Ak.", "institution": "Universitas Surabaya", "country_code": "ID", "role": "other"}]', p_co_units => '{4}');
select pg_temp.bulk_act(407, 'Inbound Credit Transfer Informatika Universiti Teknologi Malaysia 2026', 68, 33, 'inbound', '2026-07-20', '2026-09-11', 'offline', 'Laboratorium Informatika Gedung P PCU', 'ID', 107, '{4,9}', 'Mahasiswa Universiti Teknologi Malaysia mengambil dua mata kuliah Informatika (Pemrograman Mobile dan Data Mining) dengan pengakuan kredit di kampus asal.', pg_temp.daysago(2, '09:00'), 'pending', pg_temp.daysago(2, '09:00'));
select pg_temp.bulk_pset(407, '{}', '{X06269039}', '{PG564518}');
select pg_temp.bulk_act(408, 'Academic Exchange Sistem Kendali Cerdas National University of Singapore 2026', 65, 28, 'inbound', '2026-08-03', '2026-09-25', 'offline', 'Laboratorium Teknik Elektro Gedung W PCU', 'ID', 19, '{4,7}', 'Mahasiswa National University of Singapore melakukan pertukaran akademik di laboratorium Teknik Elektro, mengerjakan proyek kendali cerdas untuk sistem panel surya skala kecil.', pg_temp.daysago(5, '09:00'), 'pending', pg_temp.daysago(5, '09:00'));
select pg_temp.bulk_pset(408, '{}', '{X06269036}', '{PG703063}');
select pg_temp.bulk_act(409, 'Magang Akuntansi dan Logistik Internasional di KMUTT Bangkok', 6, 21, 'outbound', '2026-08-03', '2026-09-11', 'offline', 'KMUTT Bang Mod Campus, Bangkok', 'TH', 156, '{8,17}', 'Mahasiswa Akuntansi magang enam minggu di unit keuangan dan logistik KMUTT serta mitra industrinya, mempelajari pelaporan biaya rantai pasok lintas negara.', pg_temp.daysago(8, '09:00'), 'pending', pg_temp.daysago(8, '09:00'), p_co_units => '{4}');
select pg_temp.bulk_pset(409, '{D32239187,D32249796}', '{}', '{PG818524}');
select pg_temp.bulk_act(410, 'Short Program Animation and Game Art di University of Technology Sydney', 63, 23, 'outbound', '2026-08-17', '2026-09-11', 'offline', 'UTS City Campus, Ultimo, Sydney', 'AU', 206, '{4,9}', 'Program singkat empat minggu tentang animasi 3D dan desain aset gim, ditutup dengan presentasi prototipe gim pendek di depan dosen UTS.', pg_temp.daysago(11, '09:00'), 'pending', pg_temp.daysago(11, '09:00'));
select pg_temp.bulk_pset(410, '{C21229761,C21239657,C21239466}', '{}', '{PG452412}');
select pg_temp.bulk_act(411, 'Studi Ekskursi Industri Otomotif Thailand bersama Chulalongkorn University', 68, 24, 'outbound', '2026-08-24', '2026-08-29', 'offline', 'Faculty of Engineering, Chulalongkorn University', 'TH', 151, '{9,12}', 'Kunjungan studi ke Chulalongkorn University dan kawasan industri otomotif Rayong untuk mempelajari otomasi lini perakitan dan sistem informasi manufaktur.', pg_temp.daysago(12, '09:00'), 'pending', pg_temp.daysago(12, '09:00'), p_co_units => '{28}');
select pg_temp.bulk_pset(411, '{B11239024,B11239809,B11229632}', '{}', '{PG707752}');
select pg_temp.bulk_act(412, 'Credit Transfer Kewirausahaan Sosial di Chulalongkorn University', 5, 33, 'outbound', '2026-08-10', '2026-09-11', 'offline', 'Sasin School of Management, Chulalongkorn University, Bangkok', 'TH', 25, '{4,8}', 'Mahasiswa Manajemen mengikuti mata kuliah Kewirausahaan Sosial di Chulalongkorn University selama lima minggu dengan pengakuan kredit, termasuk proyek lapangan bersama koperasi petani di Nakhon Pathom.', pg_temp.daysago(15, '09:00'), 'revision_requested', pg_temp.daysago(6, '14:00'), p_mnote => 'NRP peserta D31239267 pada daftar peserta tidak sama dengan NRP di surat tugas (tertulis D31239276). Mohon periksa kembali NRP dan unggah ulang surat tugas yang benar.');
select pg_temp.bulk_pset(412, '{D31239924,D31239267}', '{}', '{PG295222}');
select pg_temp.bulk_act(413, 'Program Imersi Budaya Visual Filipina bersama Ateneo de Manila University', 63, 22, 'outbound', '2026-08-17', '2026-09-04', 'offline', 'Ateneo de Manila University, Loyola Heights, Quezon City', 'PH', 133, '{4,11}', 'Program imersi tiga minggu tentang budaya visual Filipina: kunjungan museum, lokakarya ilustrasi jeepney art, dan kolaborasi poster dengan mahasiswa Ateneo.', pg_temp.daysago(18, '09:00'), 'revision_requested', pg_temp.daysago(9, '14:00'), p_mnote => 'Transkrip nilai C21249938 hanya memuat halaman 1 dari 2; halaman rincian mata kuliah dan tanda tangan registrar Ateneo belum ada. Mohon unggah transkrip lengkap.');
select pg_temp.bulk_pset(413, '{C21259377,C21249938}', '{}', '{PG780858}');
select pg_temp.bulk_act(414, 'Academic Exchange Laboratorium Robotika Kanazawa Institute of Technology', 65, 28, 'outbound', '2026-08-31', '2026-09-18', 'offline', 'Ogigaoka Campus, Kanazawa Institute of Technology', 'JP', 105, '{4,9}', 'Mahasiswa Teknik Elektro bergabung dengan laboratorium robotika Kanazawa Institute of Technology selama tiga minggu untuk mengembangkan pengendali lengan robot berbasis visi komputer.', pg_temp.daysago(9, '09:00'), 'revision_requested', pg_temp.daysago(3, '14:00'), p_mnote => 'Tanggal kegiatan (31 Agustus - 18 September 2026) tidak sesuai dengan surat tugas No. 412/FTI/VIII/2026 yang mencantumkan 1 - 19 September 2026. Mohon sesuaikan tanggal kegiatan atau unggah surat tugas revisi.');
select pg_temp.bulk_pset(414, '{B12239147,B12239970}', '{}', '{PG413450}');
select pg_temp.bulk_act(415, 'Pelatihan Daring Analitik Data Pelanggan bersama Universiti Brunei Darussalam', 5, 69, 'inbound', '2026-08-18', '2026-08-20', 'online', 'Microsoft Teams', null, 174, '{4,8}', 'Pelatihan daring tiga hari tentang segmentasi pelanggan dan analitik churn menggunakan data ritel anonim, dibawakan dosen UBD School of Business and Economics untuk mahasiswa dan dosen Manajemen.', pg_temp.wib('2026-08-27', '09:00'), null, null, p_ext => '[{"full_name": "Dr. Nurul Aisyah binti Haji Abdullah", "institution": "Universiti Brunei Darussalam", "country_code": "BN", "role": "speaker"}]');
select pg_temp.bulk_act(416, 'Kuliah Tamu Cybersecurity Operations Center dari University of Amsterdam', 68, 15, 'inbound', '2026-08-12', '2026-08-12', 'offline', 'Auditorium Gedung P PCU', 'ID', 191, '{4,9}', 'Kuliah tamu tentang operasional Security Operations Center, simulasi penanganan insiden, dan jalur karier keamanan siber bagi mahasiswa Informatika.', null, null, null, p_ext => '[{"full_name": "Dr. Pieter van der Berg", "institution": "University of Amsterdam", "country_code": "NL", "role": "speaker"}]');
select pg_temp.bulk_act(417, 'Seminar Bersama Ekonomi Digital Taiwan-Indonesia dengan National Taiwan University', 5, 10, 'inbound', '2026-09-22', '2026-09-22', 'hybrid', 'Ruang Seminar Gedung T PCU', 'ID', 30, '{8,17}', 'Seminar hibrida yang membandingkan ekosistem platform digital dan regulasi e-commerce di Taiwan dan Indonesia, dengan pembicara dari National Taiwan University.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Chen Wei-ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]', p_co_units => '{4}');
select pg_temp.bulk_act(418, 'Penyusunan Kurikulum Bersama Desain Interaktif dengan Hochschule Bremen', 63, 32, 'inbound', '2026-09-14', '2026-09-25', 'offline', 'Ruang Rapat Gedung P PCU', 'ID', 205, '{4,17}', 'Lokakarya penyusunan kurikulum bersama mata kuliah Desain Interaktif dan UX, menyelaraskan capaian pembelajaran DKV PCU dengan program Hochschule Bremen untuk rencana pengakuan kredit.', null, null, null, p_files => '{ia}', p_ext => '[{"full_name": "Prof. Dr. Katrin Schulte", "institution": "Hochschule Bremen", "country_code": "DE", "role": "visiting_lecturer"}]');
select pg_temp.bulk_act(419, 'Winter Program Renewable Energy Systems di Kyoto Sangyo University', 65, 23, 'outbound', '2026-11-23', '2026-12-04', 'offline', 'Kamigamo Campus, Kyoto Sangyo University', 'JP', 11, '{7,13}', 'Program musim dingin dua minggu tentang integrasi energi surya dan penyimpanan baterai, termasuk praktikum laboratorium dan kunjungan ke fasilitas smart grid di Kyoto.', null, null, null, p_files => '{}');
select pg_temp.bulk_pset(419, '{B12239276,B12239596}', '{}', '{PG204517}');
select pg_temp.bulk_act(420, 'Kuliah Tamu Model Bisnis Industrie 4.0 dari Ludwig Maximilian University of Munich', 5, 7, 'inbound', '2026-12-08', '2026-12-08', 'offline', 'Auditorium Gedung W PCU', 'ID', 42, '{8,9}', 'Kuliah tamu perdana dalam kerja sama baru dengan Ludwig Maximilian University of Munich tentang model bisnis berbasis Industrie 4.0 dan transformasi digital UKM manufaktur Jerman.', null, null, null, p_files => '{}', p_ext => '[{"full_name": "Prof. Dr. Thomas Weber", "institution": "Ludwig Maximilian University of Munich", "country_code": "DE", "role": "speaker"}]', p_co_units => '{4}');

select pg_temp.bulk_verify(396, 420);

-- >>> supabase/seed-supabase/11_refreeze_tambahan.sql
-- seed-supabase/11_refreeze_tambahan (simks-partnership): re-freezes the AY 2025/2026 snapshots once more after the
-- additional bulk kegiatan (10_kegiatan_tambahan_1..8, R-58), as of their original freeze moments, so Ganjil and Setahun
-- include them; the earlier snapshots stay as superseded. No-op on a fresh install (90_freeze.sql freezes later), when
-- the additional kegiatan are absent, and when already done.
-- Self-contained and idempotent, so it can be run on its own: Supabase SQL Editor or one statement batch.
-- Writes only realisasi.*; SIM Kerjasama tables are only read.

do $$
declare s realisasi.kpi_snapshots; v_reason text := 'Bekukan ulang setelah impor kegiatan tambahan 2025/2026';
begin
  for s in select * from realisasi.kpi_snapshots
            where academic_year_id = 1 and superseded_by is null and refreeze_reason is distinct from v_reason
              and exists (select 1 from realisasi.activities a where a.id = ('b5000000-0000-4000-8000-' || lpad('221', 12, '0'))::uuid)
            order by frozen_at
  loop
    perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at, (select id from kerjasama.profiles where akun_id = 1),
                              v_reason, s.id);
  end loop;
end $$;

-- >>> supabase/seed-supabase/90_freeze.sql
-- seed-supabase/90_freeze (simks-partnership): freeze AY 2025/2026 like the scheduled job would have (idempotent).
-- 90_freeze: historical snapshots of AY 2025/2026 (run by the "scheduled job": auth.uid() is null, frozen_by null).
select realisasi.freeze_snapshot(1, 'ganjil_ytd', '2026-03-02 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(1, 'genap_full_year', '2026-08-30 01:00+07')
 where not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 1 and kind = 'genap_full_year' and superseded_by is null);

-- The seeded freezes notify at reset time; date those notifications (and their outbox rows) at the snapshot's frozen_at
-- and mark them read for io_admin, so the demo shows one notification per snapshot (requirements-review L-6). Idempotent.
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.academic_year_id = 1 and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.academic_year_id = 1 and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;

commit;

-- Verification: the last result is the schema fingerprint (must match docs/SUPABASE_INTEGRATION.md)
select 'functions' k, count(*)::text n, md5(string_agg(n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')='||md5(replace(p.prosrc, chr(13), '')), ',' order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))) h
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('realisasi','kerjasama','mock_baak','mock_hr')
union all
select 'columns', count(*)::text, md5(string_agg(table_schema||'.'||table_name||'.'||column_name||':'||data_type, ',' order by table_schema, table_name, column_name))
  from information_schema.columns where table_schema in ('realisasi','kerjasama','mock_baak','mock_hr')
union all
select 'policies', count(*)::text, md5(string_agg(schemaname||'.'||tablename||'.'||policyname, ',' order by schemaname, tablename, policyname))
  from pg_policies where schemaname in ('realisasi','kerjasama');
