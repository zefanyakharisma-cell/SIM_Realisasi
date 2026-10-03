-- SIM Realisasi Supabase install, PART 5 OF 5 (commit 3f12ec4).
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
  ('PG124885', 'Angelina Wibowo, S.E.', 'Prodi Desain Komunikasi Visual', 'Lektor Kepala', 'inactive'),
  ('PG190875', 'Ir. Reza Prasetyo, M.M.', 'Prodi Informatika', 'Dosen', 'active'),
  ('PG204517', 'Ir. Bambang Sutrisno, M.T.', 'Prodi Teknik Elektro', 'Lektor Kepala', 'active'),
  ('PG214411', 'Eunike Susanto, M.M.', 'Prodi Manajemen', 'Staf Administrasi', 'active'),
  ('PG217839', 'Wilson Tanjung, M.M.', 'Fakultas Bisnis & Ekonomi', 'Staf Administrasi', 'active'),
  ('PG295222', 'Ir. Felicia Wibowo, M.M.', 'Prodi Manajemen', 'Dosen', 'active'),
  ('PG378607', 'Dr. Patricia Kurniawan, S.E.', 'Prodi Informatika', 'Dosen', 'active'),
  ('PG413450', 'Dr. Gabriel Saputra, M.M.', 'Prodi Teknik Elektro', 'Lektor Kepala', 'active'),
  ('PG427328', 'Jonathan Prasetyo, S.E.', 'International Office', 'Staf Administrasi', 'active'),
  ('PG452412', 'Andreas Prasetyo, M.Sc.', 'Prodi Desain Komunikasi Visual', 'Kepala Program Studi', 'active'),
  ('PG488192', 'Ir. Yosua Gunawan, M.M.', 'Prodi Informatika', 'Tenaga Kependidikan', 'active'),
  ('PG561867', 'Edwin Purnomo, M.Ds.', 'Prodi Manajemen', 'Staf Administrasi', 'active'),
  ('PG564518', 'Ir. Kevin Santoso, M.Ds.', 'Prodi Informatika', 'Dosen', 'active'),
  ('PG637448', 'Leonardo Prasetyo, M.Sc.', 'International Office', 'Staf Administrasi', 'active'),
  ('PG657970', 'Yohana Wibowo, M.Sc.', 'Prodi Informatika', 'Dosen', 'active'),
  ('PG703063', 'Kevin Wibowo, S.E.', 'Prodi Teknik Elektro', 'Dosen', 'active'),
  ('PG707752', 'Patricia Saputra, M.Ds.', 'Fakultas Teknologi Industri', 'Tenaga Kependidikan', 'active'),
  ('PG710955', 'Yosua Sugianto, M.T.', 'Prodi Informatika', 'Lektor Kepala', 'active'),
  ('PG712740', 'Jonathan Gunawan, M.M.', 'Prodi Informatika', 'Dosen', 'active'),
  ('PG760736', 'Ir. Hendra Sugianto, M.Ds.', 'Prodi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG761401', 'Eunike Gunawan, M.T.', 'Fakultas Seni & Desain', 'Kepala Program Studi', 'active'),
  ('PG780858', 'Natalia Susanto, S.E.', 'Prodi Desain Komunikasi Visual', 'Dosen', 'active'),
  ('PG803275', 'Yohana Sugianto, S.E.', 'International Office', 'Tenaga Kependidikan', 'inactive'),
  ('PG818524', 'Olivia Hidayat, M.Sc.', 'Fakultas Bisnis & Ekonomi', 'Dosen', 'active'),
  ('PG974721', 'Michael Tanoto, M.T.', 'Fakultas Bisnis & Ekonomi', 'Staf Administrasi', 'active')
on conflict (employee_id) do update set full_name = excluded.full_name, unit_name = excluded.unit_name,
  position = excluded.position, status = excluded.status;

-- >>> supabase/seed-supabase/02b_registry_more.sql
-- seed-supabase/02b_registry_more (simks-partnership): a mock BAAK registry big enough for realistic participant
-- lists (used by 05_activities_history and 06_participants). Mockup only; written into mock_baak.* only. Idempotent
-- (existing NRPs are skipped).
--   + 1,694 PETRA students: 19 prodi x intakes 2020-2026, NRP <prefix><yy>8<nnn> (e.g. D31238001); intakes older than
--     the prodi length are 'graduated', every 13th student 'inactive'.
--   + 750 inbound exchange students: 25 per real SIMKS partner per intake 2024-2026 (50 for Kyoto Sangyo University),
--     NRP X<1x><yy>8<nnn>, home institution = the partner's SIMKS name (R-17: every inbound student holds an NRP).

with h6_prodi (prefix, fcode, fname, prodi, per_intake, years) as (values
  ('A11', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Teknik Sipil', 12, 4),
  ('A12', 'A', 'Fakultas Teknik Sipil dan Perencanaan', 'Arsitektur', 16, 4),
  ('B11', 'B', 'Fakultas Teknologi Industri', 'Informatika', 20, 4),
  ('B12', 'B', 'Fakultas Teknologi Industri', 'Teknik Elektro', 12, 4),
  ('B13', 'B', 'Fakultas Teknologi Industri', 'Teknik Industri', 16, 4),
  ('C21', 'C', 'Fakultas Seni dan Desain', 'Desain Komunikasi Visual', 20, 4),
  ('E41', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Sastra Inggris', 10, 4),
  ('E42', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Ilmu Komunikasi', 10, 4),
  ('D31', 'D', 'Fakultas Bisnis dan Ekonomi', 'Manajemen', 24, 4),
  ('D32', 'D', 'Fakultas Bisnis dan Ekonomi', 'Akuntansi', 16, 4),
  ('D33', 'D', 'Fakultas Bisnis dan Ekonomi', 'International Business Management', 16, 4),
  ('D34', 'D', 'Fakultas Bisnis dan Ekonomi', 'Hotel Management', 16, 4),
  ('F51', 'F', 'Fakultas Keguruan dan Ilmu Pendidikan', 'Pendidikan Guru Sekolah Dasar', 10, 4),
  ('G61', 'G', 'Fakultas Kedokteran', 'Kedokteran', 6, 4),
  ('H71', 'H', 'Program Pascasarjana', 'Magister Manajemen', 6, 2),
  ('B14', 'B', 'Fakultas Teknologi Industri', 'Teknik Mesin', 10, 4),
  ('C22', 'C', 'Fakultas Seni dan Desain', 'Desain Interior', 10, 4),
  ('E43', 'E', 'Fakultas Humaniora dan Industri Kreatif', 'Bahasa Mandarin', 6, 4),
  ('G62', 'G', 'Fakultas Kedokteran Gigi', 'Kedokteran Gigi', 6, 4)),
names as (
  select array['Adrian','Agnes','Albert','Amanda','Andreas','Angela','Bryan','Calvin','Catherine','Christian','Clara',
               'Daniel','Debora','Edward','Elisabeth','Evelyn','Felix','Florencia','Gabriel','Gloria','Hans','Hana',
               'Ivan','Jessica','Jonathan','Josephine','Kevin','Kezia','Leonardo','Lidya','Matthew','Michelle','Nathan',
               'Natalia','Patrick','Priscilla','Rafael','Rebecca','Samuel','Stefani','Timothy','Vanessa','Vincent',
               'Yohana','Yosua','Zefanya'] f,
         array['Gunawan','Halim','Hartono','Hidayat','Kurniawan','Kusuma','Lesmana','Liem','Pranoto','Prasetyo',
               'Purnomo','Salim','Santoso','Saputra','Setiawan','Sugianto','Susanto','Sutanto','Tanjung','Tanoto',
               'Tjahjono','Wibowo','Widjaja','Wijaya','Winata','Yulianto','Budiman','Chandra','Darmawan','Effendi'] l)
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution,
                                home_country_code, intake_year, status)
select p.prefix || right(y::text, 2) || '8' || lpad(i::text, 3, '0'),
       n.f[1 + abs(hashtext(p.prefix || y || i || 'f')) % cardinality(n.f)] || ' ' ||
       n.l[1 + abs(hashtext(p.prefix || y || i || 'l')) % cardinality(n.l)],
       p.fcode, p.fname, p.prodi, 'regular', null, null, y,
       case when y <= 2026 - p.years then 'graduated' when i % 13 = 0 then 'inactive' else 'active' end
  from h6_prodi p cross join generate_series(2020, 2026) y cross join generate_series(1, p.per_intake) i cross join names n
on conflict (nrp) do nothing;

with h6_partner (idx, name, cc, f, l, per_year) as (values
  (11, 'Kyoto Sangyo University', 'JP', '{Haruto,Yui,Sota,Hina,Ren,Aoi,Yuto,Mio,Kaito,Sakura,Riku,Yuna}',
       '{Sato,Suzuki,Takahashi,Tanaka,Watanabe,Ito,Yamamoto,Nakamura,Kobayashi,Kato}', 50),
  (12, 'Yonsei University', 'KR', '{Min-jun,Seo-yeon,Ji-ho,Ha-eun,Do-yun,Ji-woo,Seo-jun,Su-ah,Ye-jun,Chae-won}',
       '{Kim,Lee,Park,Choi,Jung,Kang,Cho,Yoon,Jang,Lim}', 25),
  (13, 'National Taiwan University', 'TW', '{Chia-hao,Yu-ting,Po-han,Hsin-yi,Cheng-en,Pei-shan,Tzu-yang,Wan-ting}',
       '{Chen,Lin,Huang,Chang,Lee,Wang,Wu,Liu,Tsai,Yang}', 25),
  (14, 'National University of Singapore', 'SG', '{Wei Jie,Xin Yi,Jun Hao,Hui Min,Ryan,Sarah,Marcus,Nur Aisyah,Arjun,Chloe}',
       '{Tan,Lim,Lee,Ng,Ong,Wong,Goh,Chua,Rahman,Nair}', 25),
  (15, 'Chulalongkorn University', 'TH', '{Kittipong,Napat,Siriporn,Thanawat,Pimchanok,Chayanin,Warut,Kanokwan}',
       '{Srisuk,Wongsa,Chaiyaporn,Rattanakul,Saengthong,Phromma,Boonmee,Kaewkla}', 25),
  (16, 'Ateneo de Manila University', 'PH', '{Maria,Jose,Angelica,Miguel,Patricia,Gabriel,Bianca,Rafael,Andrea,Carlo}',
       '{Santos,Reyes,Cruz,Bautista,Garcia,Mendoza,Torres,Villanueva,Ramos,Aquino}', 25),
  (17, 'University of Amsterdam', 'NL', '{Daan,Sanne,Lucas,Emma,Sem,Julia,Milan,Lotte,Thijs,Fleur}',
       '{de Vries,Jansen,de Jong,Bakker,Visser,Smit,Meijer,Mulder,de Boer,Bos}', 25),
  (18, 'Ludwig Maximilian University of Munich', 'DE', '{Lukas,Lea,Felix,Anna,Jonas,Lena,Leon,Marie,Paul,Sophie}',
       '{Müller,Schmidt,Schneider,Fischer,Weber,Meyer,Wagner,Becker,Hoffmann,Schulz}', 25),
  (19, 'University of Sydney', 'AU', '{Oliver,Charlotte,Jack,Olivia,William,Amelia,Noah,Isla,Thomas,Mia}',
       '{Smith,Jones,Williams,Brown,Wilson,Taylor,Nguyen,Johnson,Martin,White}', 25))
insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution,
                                home_country_code, intake_year, status)
select 'X' || p.idx || right(y::text, 2) || '8' || lpad(i::text, 3, '0'),
       (p.f::text[])[1 + abs(hashtext(p.name || y || i || 'f')) % cardinality(p.f::text[])] || ' ' ||
       (p.l::text[])[1 + abs(hashtext(p.name || y || i || 'l')) % cardinality(p.l::text[])],
       'D', 'Fakultas Bisnis dan Ekonomi', 'Program Pertukaran (Inbound)', 'inbound_exchange', p.name, p.cc, y,
       case when y < 2026 then 'graduated' else 'active' end
  from h6_partner p cross join generate_series(2024, 2026) y cross join generate_series(1, p.per_year) i
on conflict (nrp) do nothing;

-- >>> supabase/seed-supabase/03_accounts.sql
-- seed-supabase/03_accounts (simks-partnership): which REAL SIMKS accounts (public.akun) use SIM Realisasi, and their
-- verification teams. Written only into realisasi.*; SIMKS roles are untouched. Idempotent: re-running resets these
-- accounts to the roles below (other account_roles rows are left alone). Revisi V.1: one verification team (Mobility).
--   akun  1 kepala-kui@petra.ac.id          io_admin   (mobility)
--   akun 11 staff-partnership@petra.ac.id   io_staff   (mobility)
--   akun 10 head-partnership@petra.ac.id    io_staff   (mobility)
--   akun  3 dekan-sbm@petra.ac.id           submitter  unit 4 (School of Business and Management)
--   akun  4 kaprodi-manajemen@petra.ac.id   submitter  unit 5 (Prodi Manajemen)
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
--   submitters akun 3 (unit 4, SBM) and akun 4 (unit 5, Prodi Manajemen); mobility team akun 10.
-- Revisi V.1: Jenis = SIMKS agenda, Inbound/Outbound per kegiatan, one kerja sama, Mobility the only verification
-- (non-mobility kegiatan verified on submit), one open student conflict between SBM and Prodi Manajemen (S-13).
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

-- rule 2.1 demo: Prodi Manajemen claims two of SBM's summer-program students (S-06) -> open conflict in the queue
select pg_temp.act(13, 'Summer Program Business in Asia (Prodi Manajemen)', 5, 23, 'outbound', '2026-07-06', '2026-07-24', 'offline',
  'Chulalongkorn University', 'TH', 25, '{4}', pg_temp.daysago(4), 'pending', pg_temp.daysago(4));
select pg_temp.pset(13, 'pending', '{D31242651,D31245931}', '{}', '{}', pg_temp.daysago(4));
select realisasi._scan_conflicts(pg_temp.aid(13)) where not exists (select 1 from realisasi.participant_conflicts where pg_temp.aid(13) in (activity_a, activity_b));

select setval('realisasi.activity_code_seq', greatest(100, (select last_value from realisasi.activity_code_seq)));

-- >>> supabase/seed-supabase/05_activities_history.sql
-- seed-supabase/05_activities_history (simks-partnership): 52 more kegiatan (RL-xxxx-0201 … 0252) spanning AY 2024/2025
-- to today, on REAL SIMKS documents, written only into realisasi.*. Idempotent: an activity that exists is skipped.
--
-- * Adds AY 2024/2025 (id 3, semesters 5/6) to the calendar so that year's kegiatan get a period (R-09).
-- * Every kegiatan's dates lie inside its agreement's validity (checked with realisasi.documents_valid_between, R-04).
--   Before 2025-10-17 only document 11 (Kyoto Sangyo University, from 2024-08-15) is valid, so AY 2024/2025 is built
--   on it; later kegiatan spread over UGM, Chulalongkorn, NTU, Yonsei, Amsterdam, NUS, Astra, Unilever, LMU, Ateneo,
--   Sydney and the renewals 33/34.
-- * Mix: mobility and non-mobility Jenis, inbound/outbound, offline/online/hybrid, 25 units across SBM, FTI, FHIK,
--   FTSP, FKIP, Kedokteran, LPPM and KUI, co-units, external speakers/lecturers/researchers, late submissions (R-10),
--   Mobility approvals, two kegiatan approved after a revision round, one revision still open, two in the queue,
--   drafts (one future, one ongoing, one abandoned), a post-freeze edit.
-- * Students are taken from mock_baak with intake years that fit the dates, and no NRP is claimed by two units on
--   overlapping dates (asserted at the end), so no unintended rule 2.1 conflicts appear.
-- * Participant lists are filled to realistic sizes and snapshots are (re-)frozen by 06_participants.sql.
-- Actors: submitters akun 3 (unit 4) and akun 4 (unit 5 and its prodi); every other unit's kegiatan was entered by
-- KUI (akun 1, io_admin). Mobility verifiers akun 10 and 11.
-- Ids: activities c5000000-0000-4000-8000-0000000002NN (201-252), event groups f5000000-…, codes RL-<year created>-02NN.

insert into realisasi.academic_years (id, label, start_date, end_date) values (3, '2024/2025', '2024-08-01', '2025-07-31')
on conflict (id) do update set label = excluded.label, start_date = excluded.start_date, end_date = excluded.end_date;
insert into realisasi.semesters (id, academic_year_id, term, start_date, end_date, cutoff_date) values
  (5, 3, 'ganjil', '2024-08-01', '2025-01-31', '2025-03-02'),
  (6, 3, 'genap',  '2025-02-01', '2025-07-31', '2025-08-30')
on conflict (id) do update set academic_year_id = excluded.academic_year_id, term = excluded.term,
  start_date = excluded.start_date, end_date = excluded.end_date, cutoff_date = excluded.cutoff_date;
select setval('realisasi.academic_years_id_seq', greatest((select max(id) from realisasi.academic_years), 1));
select setval('realisasi.semesters_id_seq', greatest((select max(id) from realisasi.semesters), 1));

-- seed-supabase/lib/activity_helpers.inc: session-local (pg_temp) helpers shared by 05_activities_history,
-- 06_participants and 07_activities_more. Included with \ir; defines functions only, writes nothing.
--   h_act       one kegiatan with units, kerja sama, SDGs, external persons, files, participants and history
--   h_fill      add students (by prodi / partner, never across units on overlapping dates) up to a target size
--   h_assert_no_conflicts, h_refreeze_stale, h_date_freeze_notifications   checks and snapshot upkeep
-- Re-including is harmless (create or replace). No temp tables: a temp table that outlives its transaction stalls
-- Supabase's SQL API connection, so lookup data lives in functions.

create or replace function pg_temp.h_aid(n int) returns uuid language sql immutable as $$
  select ('c5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_gid(n int) returns uuid language sql immutable as $$
  select ('f5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.h_pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.h_wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null, p_frozen boolean default false)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.h_aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, p_frozen, p_at) $$;

-- the submitting account for a unit: SBM -> akun 3, Prodi Manajemen and its programs -> akun 4, else KUI (akun 1)
create or replace function pg_temp.h_creator(p_unit int) returns uuid language sql stable as $$
  select pg_temp.h_akun(case when p_unit = 4 then 3
                           when p_unit = 5 or exists (select 1 from kerjasama.units u where u.id = p_unit and u.parent_id = 5) then 4
                           else 1 end) $$;

-- which prodi a unit's outbound students come from (nearest mapped unit up the tree; a faculty takes all its prodi)
create or replace function pg_temp.h_unit_prodi() returns table(unit_id int, prodi text) language sql immutable as $$
  select * from (values
  (4, 'Manajemen'), (4, 'Akuntansi'), (4, 'International Business Management'), (4, 'Hotel Management'),
  (5, 'Manajemen'), (6, 'Akuntansi'), (7, 'International Business Management'), (8, 'Hotel Management'),
  (48, 'Magister Manajemen'), (51, 'Magister Manajemen'),
  (28, 'Informatika'), (28, 'Teknik Elektro'), (28, 'Teknik Industri'),
  (65, 'Teknik Elektro'), (67, 'Teknik Industri'), (68, 'Informatika'),
  (32, 'Desain Komunikasi Visual'), (32, 'Sastra Inggris'), (32, 'Ilmu Komunikasi'),
  (57, 'Ilmu Komunikasi'), (61, 'Sastra Inggris'), (63, 'Desain Komunikasi Visual'),
  (35, 'Arsitektur'), (35, 'Teknik Sipil'), (54, 'Arsitektur'), (55, 'Teknik Sipil'),
  (36, 'Pendidikan Guru Sekolah Dasar'), (73, 'Pendidikan Guru Sekolah Dasar'),
  (30, 'Kedokteran'), (76, 'Kedokteran'),
  (28, 'Teknik Mesin'), (69, 'Teknik Mesin'), (59, 'Desain Interior'), (60, 'Desain Interior'), (62, 'Desain Komunikasi Visual'),
  (58, 'Bahasa Mandarin'), (34, 'Kedokteran Gigi'), (74, 'Kedokteran Gigi'), (29, 'Magister Manajemen')) v(unit_id, prodi) $$;

create or replace function pg_temp.h_prodi_of(p_unit int) returns text[] language sql stable as $$
  with recursive up(id, parent_id, depth) as (
    select u.id, u.parent_id, 0 from kerjasama.units u where u.id = p_unit
    union all select u.id, u.parent_id, up.depth + 1 from kerjasama.units u join up on u.id = up.parent_id where up.depth < 5)
  select array_agg(m.prodi) from pg_temp.h_unit_prodi() m
   where m.unit_id = (select up.id from up where exists (select 1 from pg_temp.h_unit_prodi() x where x.unit_id = up.id)
                       order by up.depth limit 1) $$;

-- Add students to an activity's current participant set until it holds p_target counted students (+ staff up to
-- p_staff). Returns how many students were added.
create or replace function pg_temp.h_fill(p_activity uuid, p_target int, p_staff int default 0) returns int
language plpgsql as $$
declare a realisasi.activities; v_set uuid; v_section text; v_have int; v_need int; v_added int := 0;
        v_prodi text[]; v_partner text; v_ref int; v_years int;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not found then return 0; end if;
  select id into v_set from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  if v_set is null then raise exception 'activity %: no participant set', a.code; end if;
  v_section := case when a.direction = 'outbound' then 'internal' else 'inbound' end;
  select count(*) into v_have from realisasi.participant_students where set_version_id = v_set and section::text = v_section;
  v_need := p_target - v_have;

  -- academic intake that is enrolled on the start date (the AY starting in August)
  v_ref := extract(year from a.start_date)::int - case when extract(month from a.start_date) < 8 then 1 else 0 end;
  if v_section = 'internal' then
    v_prodi := pg_temp.h_prodi_of(a.submitter_unit_id);
    if v_prodi is null then raise exception 'activity %: no prodi mapping for unit %', a.code, a.submitter_unit_id; end if;
  else
    select p.name into v_partner from realisasi.activity_documents ad
      join kerjasama.document_partners dp on dp.document_id = ad.original_document_id and dp.is_lead
      join kerjasama.partners p on p.id = dp.partner_id
     where ad.activity_id = p_activity limit 1;
  end if;

  if v_need > 0 then
    with taken as (   -- students another unit claims on overlapping dates (any version, drafts included)
      select ps.nrp from realisasi.participant_students ps
        join realisasi.participant_set_versions v on v.id = ps.set_version_id
        join realisasi.activities o on o.id = v.activity_id
       where o.id <> a.id and o.submitter_unit_id <> a.submitter_unit_id
         and o.start_date <= a.end_date and a.start_date <= o.end_date),
    pick as (
      select s.* from mock_baak.students s
       where s.status <> 'inactive'
         and not exists (select 1 from realisasi.participant_students x where x.set_version_id = v_set and x.nrp = s.nrp)
         and s.nrp not in (select nrp from taken)
         and case when v_section = 'internal' then
                s.category = 'regular' and s.prodi_name = any(v_prodi)
                and s.intake_year <= v_ref
                and s.intake_year > v_ref - case when s.prodi_name = 'Magister Manajemen' then 2 else 4 end
                and s.intake_year < v_ref   -- no first-semester students abroad
              else
                s.category = 'inbound_exchange' and s.home_institution = v_partner
                and s.intake_year = extract(year from a.start_date)::int
              end
       order by exists (select 1 from realisasi.participant_students u where u.nrp = s.nrp), md5(s.nrp || a.code)
       limit v_need)
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_set, v_section::realisasi.student_section, p.nrp, p.full_name, p.faculty_name, p.prodi_name,
           p.home_institution, case when v_section = 'inbound' then 'HS-' || right(p.nrp, 4) end, p.home_country_code
      from pick p;
    get diagnostics v_added = row_count;
    if v_added < v_need then
      raise exception 'activity %: only % of % eligible students available', a.code, v_added, v_need;
    end if;
  end if;

  if p_staff > (select count(*) from realisasi.participant_staff where set_version_id = v_set) then
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e
     where e.status = 'active'
       and not exists (select 1 from realisasi.participant_staff x where x.set_version_id = v_set and x.employee_id = e.employee_id)
     order by md5(e.employee_id || a.code)
     limit p_staff - (select count(*) from realisasi.participant_staff where set_version_id = v_set);
  end if;
  return v_added;
end $$;

-- One kegiatan with its units, kerja sama, SDGs, external persons, files, participants (mobility) and history.
--   p_mstatus (mobility only): approved | pending | revision_requested; p_msince = when Mobility acted (or submit time)
--   p_rev: an earlier revision round {"note", "at", "resubmit"} before the final p_mstatus
--   p_auto / p_auto_staff: instead of listing NRPs, let pg_temp.h_fill pick that many students (and staff); with p_rev the
--   revised version 1 holds all but one of them (the student the revision note was about)
create or replace function pg_temp.h_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz,
  p_mstatus text default null, p_msince timestamptz default null, p_mnote text default null,
  p_int text[] default '{}', p_inb text[] default '{}', p_staff text[] default '{}',
  p_co int[] default '{}', p_ext jsonb default '[]', p_files text[] default '{ia,ir}', p_rev jsonb default null,
  p_auto int default 0, p_auto_staff int default 0)
returns void language plpgsql as $$
declare v_id uuid := pg_temp.h_aid(p_n); v_g uuid := pg_temp.h_gid(p_n);
        v_creator uuid := pg_temp.h_creator(p_unit); v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_verifier uuid := pg_temp.h_akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb; v_ver int := 1; v_pset uuid; v_status text;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'activity %: no account for unit %', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit) then raise exception 'activity %: SIMKS unit % missing', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'activity %: SIMKS agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'activity %: SIMKS document % not valid for % – %', p_n, p_doc, p_start, p_end;
  end if;
  if p_submitted is not null and p_end > (p_submitted at time zone 'Asia/Jakarta')::date then
    raise exception 'activity %: submitted before it ended (R-08)', p_n;
  end if;
  if v_mob and p_submitted is not null and ((cardinality(p_int) + cardinality(p_inb) = 0 and p_auto = 0) or p_mstatus is null) then
    raise exception 'activity %: a submitted mobility kegiatan needs students and a Mobility status', p_n;
  end if;

  -- drafts were opened a few days before the end date (never in the future); submissions three days before submitting
  v_created := case when p_submitted is not null then p_submitted - interval '3 days'
                    else least(pg_temp.h_wib(p_end) - interval '3 days', pg_temp.h_daysago(2)) end;
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');

  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then case when v_mob then p_msince else p_submitted end end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created,
          coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter)
  select v_id, p_unit, true union all select v_id, u, false from unnest(p_co) u where u <> p_unit;
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
    values (v_path, split_part(v_path, '/', 1), pg_temp.h_pdf(), 'application/pdf', length(pg_temp.h_pdf()), v_creator,
            v_created + interval '1 day')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.h_pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  -- participants (mobility only): an earlier revised version, then the current one (a draft set for a draft)
  if v_mob and cardinality(p_int) + cardinality(p_inb) + cardinality(p_staff) + p_auto > 0 then
    for v_ver in 1 .. case when p_rev is not null then 2 else 1 end loop
      v_pset := md5(v_id::text || ':v' || v_ver)::uuid;
      v_status := case when p_submitted is null then 'draft' when p_rev is not null and v_ver = 1 then 'revision_requested' else p_mstatus end;
      insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at,
                  reviewed_by, reviewed_at, review_note)
      values (v_pset, v_id, v_ver, v_status::realisasi.pset_status, case when p_submitted is not null then v_creator end,
              case when v_ver = 2 then (p_rev ->> 'resubmit')::timestamptz else p_submitted end,
              case when v_status in ('approved', 'revision_requested') then v_verifier end,
              case when p_rev is not null and v_ver = 1 then (p_rev ->> 'at')::timestamptz
                   when v_status in ('approved', 'revision_requested') then p_msince end,
              case when p_rev is not null and v_ver = 1 then p_rev ->> 'note' when v_status = 'revision_requested' then p_mnote end);
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
      select v_pset, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
        from unnest(p_int) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                  home_institution, home_student_number, home_country_code)
      select v_pset, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 4),
             s.home_country_code
        from unnest(p_inb) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
      select v_pset, e.employee_id, e.full_name, e.unit_name
        from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
    end loop;
    if p_auto = 0 and (select count(*) from realisasi.participant_students ps join realisasi.participant_set_versions v on v.id = ps.set_version_id
         where v.activity_id = v_id and v.version = 1) <> cardinality(p_int) + cardinality(p_inb) then
      raise exception 'activity %: an NRP is not in mock_baak.students', p_n;
    end if;
    if p_auto > 0 then
      perform pg_temp.h_fill(v_id, p_auto, p_auto_staff);
      if p_rev is not null then   -- version 1 (sent back) lacked the last student added in version 2
        insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                    home_institution, home_student_number, home_country_code)
        select md5(v_id::text || ':v1')::uuid, s.section, s.nrp, s.full_name, s.faculty_name, s.prodi_name,
               s.home_institution, s.home_student_number, s.home_country_code
          from realisasi.participant_students s where s.set_version_id = md5(v_id::text || ':v2')::uuid
         order by s.id limit greatest(p_auto - 1, 1)
        on conflict do nothing;
      end if;
    end if;
  end if;

  perform pg_temp.h_log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.h_log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if not v_mob then return; end if;
  if p_rev is not null then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, (p_rev ->> 'at')::timestamptz, p_rev ->> 'note');
    perform pg_temp.h_log(p_n, 'revision', 'mobility', 'resubmit', v_creator, (p_rev ->> 'resubmit')::timestamptz);
  end if;
  if p_mstatus = 'approved' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'approve', v_verifier, p_msince, null,
                        jsonb_build_object('version', case when p_rev is not null then 2 else 1 end));
  elsif p_mstatus = 'revision_requested' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, p_msince, p_mnote);
  end if;
end $$;

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
create or replace function pg_temp.h_assert_no_conflicts() returns void language plpgsql as $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id > a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.status <> 'draft' and x.nrp in (select realisasi._claimed_nrps(o.id))
     and not exists (select 1 from realisasi.participant_conflicts c
                      where c.nrp = x.nrp and c.activity_a = least(a.id, o.id) and c.activity_b = greatest(a.id, o.id));
  if v is not null then raise exception 'unintended student conflicts: %', v; end if;
end $$;

-- supersede system snapshots whose items differ from what the scheduled job would freeze now (oldest period first, so
-- later snapshots see the re-frozen previous period as their late-addition baseline)
-- (p_ay limits it to one academic year: on Supabase each re-freeze runs as its own short statement)
create or replace function pg_temp.h_refreeze_stale(p_reason text, p_ay int default null) returns int language plpgsql as $$
declare s realisasi.kpi_snapshots; n int := 0;
begin
  for s in select k.* from realisasi.kpi_snapshots k where k.superseded_by is null and k.frozen_by is null
                and (p_ay is null or k.academic_year_id = p_ay) order by k.frozen_at loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null, p_reason, s.id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- date system freezes' notifications (and outbox rows) at the snapshot's frozen_at, read for io_admin (as 90_freeze)
create or replace function pg_temp.h_date_freeze_notifications() returns void language sql as $$
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.frozen_by is null and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.frozen_by is null and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
$$;

-- preconditions: accounts seeded, every referenced SIMKS document selectable
do $$
declare d int;
begin
  if pg_temp.h_akun(1) is null or pg_temp.h_akun(3) is null or pg_temp.h_akun(4) is null or pg_temp.h_akun(10) is null
     or pg_temp.h_akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 3, 4, 10, 11)';
  end if;
  foreach d in array array[11, 12, 15, 17, 19, 21, 23, 25, 27, 28, 29, 30, 31, 32, 34, 36, 40, 42, 44, 51, 52] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/05_activities_history.sql', d;
    end if;
  end loop;
end $$;

-- Mobility Jenis used: 2 Student Exchange, 28 Academic Exchange, 33 Credit Transfer (student_exchange); 17 Double Degree
-- (jd_dd); 22 Immersion, 23 Short Program, 29 Cultural Exchange (short_summer); 21 Magang, 24 Studi Ekskursi
-- (other_mobility). Non-mobility: 4 Joint Research, 15 Kuliah Tamu, 27 Academic Visit, 31 Staf Exchange, 35 Joint
-- Projects, 40 Pengabdian, 69 Pelatihan, 79 Online Course.

-- ==== AY 2024/2025 Ganjil (document 11, Kyoto Sangyo University) ====================================================
select pg_temp.h_act(201, 'Student Exchange Semester Ganjil 2024 di Kyoto Sangyo University', 7, 2, 'outbound',
  '2024-09-02', '2024-12-20', 'offline', 'Kyoto Sangyo University, Kamigamo Campus', 'JP', 11, '{4,17}',
  'Dua mahasiswa International Business Management mengikuti satu semester perkuliahan reguler di Faculty of Business '
  'Administration, Kyoto Sangyo University, dengan pengakuan 20 SKS.',
  pg_temp.h_wib('2025-01-06'), 'approved', pg_temp.h_wib('2025-01-15', '14:00'),
  p_int => '{D31238836,D31239872}');

select pg_temp.h_act(202, 'Kuliah Tamu Japanese Business Culture dari Kyoto Sangyo University', 4, 15, 'inbound',
  '2024-10-14', '2024-10-15', 'hybrid', 'Auditorium Gedung P PCU', 'ID', 11, '{4,8}',
  'Kuliah tamu dua sesi tentang budaya kerja dan etika bisnis Jepang untuk mahasiswa SBM, diikuti 140 peserta luring dan daring.',
  pg_temp.h_wib('2024-10-21'),
  p_ext => '[{"full_name":"Prof. Hiroshi Tanaka","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(203, 'Riset Bersama Pariwisata Berkelanjutan Kyoto–Surabaya', 8, 4, 'outbound',
  '2024-09-16', '2025-01-31', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Penelitian komparatif praktik pariwisata berkelanjutan di Kyoto dan Surabaya; luaran berupa naskah artikel bersama.',
  pg_temp.h_wib('2025-02-10'), p_co => '{4}',
  p_ext => '[{"full_name":"Dr. Yuki Nakamura","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(204, 'Cultural Exchange Japan–Indonesia Youth Festival di Kyoto', 63, 29, 'outbound',
  '2024-11-11', '2024-11-22', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,10,17}',
  'Mahasiswa DKV menampilkan karya ilustrasi bertema budaya Nusantara dan mengikuti lokakarya desain tradisional Jepang.',
  pg_temp.h_wib('2024-11-29'), 'approved', pg_temp.h_wib('2024-12-09', '14:00'),
  p_int => '{C21233005,C21233140}', p_staff => '{PG452412}', p_co => '{32}');

select pg_temp.h_act(205, 'Staff Exchange Pengembangan Kurikulum Akuntansi ke Kyoto Sangyo University', 6, 31, 'outbound',
  '2024-12-02', '2024-12-06', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,17}',
  'Dua dosen Prodi Akuntansi melakukan benchmarking kurikulum dan diskusi rencana kelas bersama (COIL) dengan mitra.',
  pg_temp.h_wib('2024-12-16'));

select pg_temp.h_act(206, 'Webinar Internasional Ekonomi Digital Asia Timur', 5, 35, 'inbound',
  '2025-01-22', '2025-01-22', 'online', 'Zoom Meeting', null, 11, '{8,9}',
  'Webinar terbuka dengan pembicara dari Kyoto Sangyo University tentang transformasi digital UMKM di Jepang dan Indonesia.',
  pg_temp.h_wib('2025-01-27'),
  p_ext => '[{"full_name":"Assoc. Prof. Kenta Yoshida","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"},{"full_name":"Dr. Mei Okabe","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2024/2025 Genap ============================================================================================
-- approved after one revision round
select pg_temp.h_act(207, 'Short Program Spring Japanese Language and Culture di Kyoto Sangyo University', 4, 23, 'outbound',
  '2025-03-03', '2025-03-21', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Program tiga minggu bahasa dan budaya Jepang (level dasar) bagi mahasiswa SBM, termasuk kunjungan industri di Kansai.',
  pg_temp.h_wib('2025-03-27'), 'approved', pg_temp.h_wib('2025-04-10', '14:00'),
  p_int => '{D31245931,D31246584,D32237864}',
  p_rev => jsonb_build_object('note', 'Poster dan transkrip satu peserta (D32237864) belum ada di PDF; mohon unggah ulang.',
                              'at', pg_temp.h_wib('2025-04-02', '10:00'), 'resubmit', pg_temp.h_wib('2025-04-07', '15:00')));

select pg_temp.h_act(208, 'Riset Bersama Smart Manufacturing dengan Kyoto Sangyo University', 67, 4, 'inbound',
  '2025-02-10', '2025-06-27', 'hybrid', 'Lab Sistem Produksi PCU', 'ID', 11, '{9,12}',
  'Riset penjadwalan produksi berbasis IoT untuk UKM manufaktur; peneliti mitra berkunjung dua minggu ke PCU.',
  pg_temp.h_wib('2025-07-08'), p_co => '{28}',
  p_ext => '[{"full_name":"Dr. Takeshi Mori","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(209, 'Magang Internasional Pengembangan Perangkat Lunak di Kyoto', 68, 21, 'outbound',
  '2025-06-02', '2025-07-25', 'offline', 'Kyoto Sangyo University, Faculty of Information Science and Engineering', 'JP', 11, '{4,8,9}',
  'Tiga mahasiswa Informatika magang delapan minggu di laboratorium riset mitra dengan pembimbing dosen PCU.',
  pg_temp.h_wib('2025-08-01'), 'approved', pg_temp.h_wib('2025-08-12', '14:00'),
  p_int => '{B11227366,B11234310,B11235580}', p_staff => '{PG564518}');

-- late submission (deadline 2025-08-24), verified on submit
select pg_temp.h_act(210, 'Service Learning Desa Wisata bersama Mahasiswa Kyoto Sangyo University', 20, 40, 'outbound',
  '2025-07-14', '2025-07-25', 'offline', 'Desa Wisata Tulungrejo, Kota Batu', 'ID', 11, '{1,4,11}',
  'Pengabdian bersama mahasiswa PCU dan mitra: pendampingan homestay, pemetaan potensi wisata, dan pelatihan bahasa Inggris.',
  pg_temp.h_wib('2025-08-26', '16:00'));

select pg_temp.h_act(211, 'Guest Lecture Arsitektur Kayu Tradisional Jepang', 54, 15, 'inbound',
  '2025-04-21', '2025-04-24', 'offline', 'Gedung P PCU', 'ID', 11, '{9,11}',
  'Rangkaian kuliah tamu dan studio singkat tentang sambungan kayu tradisional Jepang dan relevansinya bagi rumah tropis.',
  pg_temp.h_wib('2025-05-02'),
  p_ext => '[{"full_name":"Assoc. Prof. Kenji Morimoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(212, 'Credit Transfer Semester Genap di Kyoto Sangyo University', 7, 33, 'outbound',
  '2025-04-07', '2025-07-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Program transfer kredit satu semester; mata kuliah mitra diakui penuh dalam kurikulum International Business Management.',
  pg_temp.h_wib('2025-07-24'), 'approved', pg_temp.h_wib('2025-08-05', '14:00'),
  p_int => '{D31242651,D32233592}');

-- verified; IO Admin corrected the venue after the Genap freeze (post-freeze edit)
select pg_temp.h_act(213, 'Asia-Pacific Hospitality Forum 2025', 8, 35, 'inbound',
  '2025-05-15', '2025-05-16', 'hybrid', 'Auditorium Gedung W PCU', 'ID', 11, '{8,17}',
  'Forum tahunan program Hotel Management dengan pembicara mitra, sesi panel industri, dan kompetisi studi kasus mahasiswa.',
  pg_temp.h_wib('2025-05-22'),
  p_ext => '[{"full_name":"Prof. Aiko Fujimoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');
select pg_temp.h_log(213, 'update', null, 'edit', pg_temp.h_akun(1), pg_temp.h_wib('2025-09-10', '10:30'),
  'Koreksi lokasi sesuai laporan akhir.', '{"venue": ["Auditorium PCU", "Auditorium Gedung W PCU"]}', true)
 where not exists (select 1 from realisasi.activity_log where activity_id = pg_temp.h_aid(213) and action = 'edit');

-- abandoned draft (only IA uploaded), long past its reporting deadline
select pg_temp.h_act(214, 'Workshop Penulisan Akademik bersama Kyoto Sangyo University', 61, 35, 'inbound',
  '2025-06-10', '2025-06-11', 'online', 'Zoom Meeting', null, 11, '{4}',
  'Lokakarya penulisan artikel jurnal berbahasa Inggris untuk dosen dan mahasiswa pascasarjana.',
  null, p_files => '{ia}');

-- inbound mobility in AY 2024/2025 (participants filled by 06_participants.sql)
select pg_temp.h_act(251, 'Inbound Exchange Semester Genap 2025 dari Kyoto Sangyo University', 4, 2, 'inbound',
  '2025-02-10', '2025-06-27', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,17}',
  'Mahasiswa pertukaran Kyoto Sangyo University mengikuti satu semester perkuliahan berbahasa Inggris di SBM.',
  pg_temp.h_wib('2025-07-03'), 'approved', pg_temp.h_wib('2025-07-10', '14:00'),
  p_inb => '{X11258001}');

select pg_temp.h_act(252, 'Inbound Summer Program Indonesian Hospitality and Culture 2025', 8, 23, 'inbound',
  '2025-07-07', '2025-07-18', 'offline', 'Kampus PCU Siwalankerto dan Hotel Mitra Surabaya', 'ID', 11, '{4,8,17}',
  'Program musim panas dua minggu bagi mahasiswa Kyoto Sangyo University: kelas hospitaliti, budaya Jawa Timur, dan praktik hotel.',
  pg_temp.h_wib('2025-07-24'), 'approved', pg_temp.h_wib('2025-07-31', '14:00'),
  p_inb => '{X11258002}', p_staff => '{PG214411}');

-- late: reported after the Genap 2024/2025 freeze (late addition)
select pg_temp.h_act(215, 'Riset Bersama Bahasa dan Identitas Diaspora Asia', 61, 4, 'outbound',
  '2025-05-05', '2025-07-31', 'online', 'Zoom Meeting', null, 11, '{4,10}',
  'Penelitian sosiolinguistik tentang penggunaan bahasa pada komunitas diaspora Indonesia di Jepang.',
  pg_temp.h_wib('2025-09-15', '11:00'), p_co => '{32}');

-- ==== AY 2025/2026 Ganjil ===========================================================================================
select pg_temp.h_act(216, 'Inbound Exchange Semester Ganjil 2025 dari Jepang', 4, 2, 'inbound',
  '2025-09-01', '2025-12-19', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,17}',
  'Tiga mahasiswa pertukaran dari Jepang mengikuti satu semester perkuliahan berbahasa Inggris di SBM.',
  pg_temp.h_wib('2026-01-05'), 'approved', pg_temp.h_wib('2026-01-12', '14:00'),
  p_inb => '{X01250003,X01250017,X01250024}');

select pg_temp.h_act(217, 'Kuliah Tamu Indonesian Economic Outlook bersama UGM', 6, 15, 'inbound',
  '2025-10-27', '2025-10-27', 'offline', 'Auditorium PCU', 'ID', 28, '{8}',
  'Kuliah umum prospek ekonomi Indonesia 2026 dan implikasinya bagi profesi akuntan.',
  pg_temp.h_wib('2025-11-03'),
  p_ext => '[{"full_name":"Dr. Ardi Nugroho, M.Sc.","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(218, 'Student Exchange Yonsei University Semester Fall 2025', 5, 2, 'outbound',
  '2025-10-20', '2026-01-16', 'offline', 'Yonsei University, Sinchon Campus', 'KR', 31, '{4}',
  'Pertukaran mahasiswa Prodi Manajemen pada program Fall Semester (kedatangan tertunda karena visa).',
  pg_temp.h_wib('2026-01-22'), 'approved', pg_temp.h_wib('2026-02-02', '14:00'),
  p_int => '{D31240187,D31243593}');

select pg_temp.h_act(219, 'Riset Bersama Perilaku Konsumen Berkelanjutan dengan University of Amsterdam', 42, 4, 'outbound',
  '2025-11-03', '2026-01-30', 'online', 'Microsoft Teams', null, 32, '{8,12}',
  'Survei lintas negara (Indonesia–Belanda) tentang preferensi produk ramah lingkungan pada generasi Z.',
  pg_temp.h_wib('2026-02-09'),
  p_ext => '[{"full_name":"Dr. Femke van Dijk","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(220, 'Thai Hospitality Immersion di Chulalongkorn University', 8, 22, 'outbound',
  '2025-12-01', '2025-12-12', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 29, '{4,8}',
  'Program imersi dua minggu: kelas manajemen hospitaliti, kunjungan hotel, dan proyek kelompok bersama mahasiswa Thailand.',
  pg_temp.h_wib('2025-12-18'), 'approved', pg_temp.h_wib('2026-01-07', '14:00'),
  p_int => '{D32237864,D31246584}');

select pg_temp.h_act(221, 'Magang Industri Lean Manufacturing di PT Astra International', 67, 21, 'outbound',
  '2025-12-08', '2026-01-30', 'offline', 'PT Astra International Tbk, Sunter Jakarta', 'ID', 12, '{8,9}',
  'Tiga mahasiswa Teknik Industri magang delapan minggu di lini produksi dengan proyek perbaikan berbasis lean.',
  pg_temp.h_wib('2026-02-05'), 'approved', pg_temp.h_wib('2026-02-12', '14:00'),
  p_int => '{B11235901,B11237182,B11238623}', p_staff => '{PG488192}');

select pg_temp.h_act(222, 'Academic Visit Fakultas Teknologi Industri ke National Taiwan University', 28, 27, 'outbound',
  '2025-11-17', '2025-11-21', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{4,9,17}',
  'Kunjungan pimpinan FTI untuk menjajaki program gelar ganda dan riset bersama bidang AI dan sistem manufaktur.',
  pg_temp.h_wib('2025-11-28'), p_co => '{65,67,68}');

select pg_temp.h_act(223, 'Webinar K-Culture and Creative Economy bersama Yonsei University', 57, 35, 'inbound',
  '2025-12-10', '2025-12-10', 'online', 'Zoom Meeting', null, 31, '{8,17}',
  'Webinar tentang strategi komunikasi industri kreatif Korea untuk mahasiswa Ilmu Komunikasi dan DKV.',
  pg_temp.h_wib('2025-12-15'), p_co => '{63}',
  p_ext => '[{"full_name":"Prof. Lee Ji-hoon","institution":"Yonsei University","country_code":"KR","role":"speaker"}]');

select pg_temp.h_act(224, 'Pengabdian Masyarakat Literasi Digital UMKM bersama UGM', 20, 40, 'outbound',
  '2026-01-12', '2026-01-23', 'offline', 'Kabupaten Gunungkidul, DIY', 'ID', 28, '{1,4,8}',
  'Pendampingan pemasaran digital dan pencatatan keuangan sederhana bagi 40 pelaku UMKM bersama tim UGM.',
  pg_temp.h_wib('2026-01-29'), p_co => '{4}');

-- ==== AY 2025/2026 Genap ============================================================================================
select pg_temp.h_act(225, 'Double Degree Magister Manajemen dengan National Taiwan University', 48, 17, 'outbound',
  '2026-02-23', '2026-07-17', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,17}',
  'Mahasiswa Magister Manajemen menempuh semester kedua program gelar ganda di NTU College of Management.',
  pg_temp.h_wib('2026-07-23'), 'approved', pg_temp.h_wib('2026-07-31', '14:00'),
  p_int => '{H71235980}');

select pg_temp.h_act(226, 'Seminar Internasional Sustainable Supply Chain bersama Unilever Indonesia', 67, 35, 'inbound',
  '2026-03-11', '2026-03-12', 'offline', 'Auditorium PCU', 'ID', 21, '{9,12}',
  'Seminar dan lokakarya rantai pasok berkelanjutan dengan praktisi industri; 210 peserta dari 12 perguruan tinggi.',
  pg_temp.h_wib('2026-03-17'), p_co => '{4}',
  p_ext => '[{"full_name":"Ir. Ratna Kusumawati, M.B.A.","institution":"PT Unilever Indonesia Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(227, 'Riset Bersama Urban Heat Island Surabaya dengan University of Amsterdam', 35, 4, 'inbound',
  '2026-03-02', '2026-06-26', 'hybrid', 'Lab Lingkungan Binaan PCU', 'ID', 17, '{11,13}',
  'Pengukuran suhu permukaan kota dan simulasi desain ruang terbuka hijau; peneliti mitra berkunjung tiga minggu.',
  pg_temp.h_wib('2026-07-06'), p_co => '{54,55}',
  p_ext => '[{"full_name":"Dr. Sanne Bakker","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(228, 'Student Exchange Semester Genap di National University of Singapore', 68, 2, 'outbound',
  '2026-02-23', '2026-05-08', 'offline', 'National University of Singapore, School of Computing', 'SG', 19, '{4,9}',
  'Dua mahasiswa Informatika mengikuti perkuliahan reguler di School of Computing NUS.',
  pg_temp.h_wib('2026-05-15'), 'approved', pg_temp.h_wib('2026-05-25', '14:00'),
  p_int => '{B11240422,B11244167}');

select pg_temp.h_act(229, 'Kuliah Tamu Precision Medicine dari National University of Singapore', 76, 15, 'inbound',
  '2026-04-08', '2026-04-09', 'hybrid', 'Gedung Fakultas Kedokteran PCU', 'ID', 19, '{3}',
  'Kuliah tamu kedokteran presisi dan genomik klinis bagi mahasiswa dan dosen Fakultas Kedokteran.',
  pg_temp.h_wib('2026-04-15'),
  p_ext => '[{"full_name":"Assoc. Prof. Tan Wei Ming","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(230, 'Studi Ekskursi Arsitektur Kyoto dan Osaka', 54, 24, 'outbound',
  '2026-03-16', '2026-03-27', 'offline', 'Kyoto Sangyo University', 'JP', 27, '{11}',
  'Studi lapangan arsitektur kontemporer dan konservasi kawasan bersejarah di Kyoto dan Osaka.',
  pg_temp.h_wib('2026-04-01'), 'approved', pg_temp.h_wib('2026-04-09', '14:00'),
  p_int => '{A12223059}');

-- approved after one revision round
select pg_temp.h_act(231, 'Bangkok Summer Business Camp di Chulalongkorn University', 7, 23, 'outbound',
  '2026-06-29', '2026-07-10', 'offline', 'Chulalongkorn University, Sasin School of Management', 'TH', 25, '{4,8}',
  'Program musim panas dua minggu: kelas kewirausahaan ASEAN, kunjungan perusahaan, dan pitching proyek lintas negara.',
  pg_temp.h_wib('2026-07-15'), 'approved', pg_temp.h_wib('2026-07-30', '14:00'),
  p_int => '{D31240187,D31239872}',
  p_rev => jsonb_build_object('note', 'Transkrip peserta D31240187 belum ditandatangani mitra; mohon unggah ulang PDF.',
                              'at', pg_temp.h_wib('2026-07-21', '10:00'), 'resubmit', pg_temp.h_wib('2026-07-27', '13:00')));

select pg_temp.h_act(232, 'Pelatihan Sertifikasi K3 Kelistrikan bersama PT Astra International', 65, 69, 'inbound',
  '2026-05-18', '2026-05-20', 'offline', 'Lab Teknik Elektro PCU', 'ID', 23, '{8,9}',
  'Pelatihan dan uji sertifikasi K3 kelistrikan untuk mahasiswa tingkat akhir Teknik Elektro.',
  pg_temp.h_wib('2026-05-26'),
  p_ext => '[{"full_name":"Bambang Hartono, S.T.","institution":"PT Astra International Tbk","country_code":"ID","role":"other","notes":"Instruktur bersertifikat K3"}]');

select pg_temp.h_act(233, 'Visiting Researcher Akuntansi Forensik dari Chulalongkorn University', 6, 4, 'inbound',
  '2026-04-20', '2026-05-29', 'offline', 'Gedung P PCU', 'ID', 25, '{8,16}',
  'Peneliti mitra berkunjung enam minggu untuk riset deteksi kecurangan laporan keuangan di ASEAN.',
  pg_temp.h_wib('2026-06-05'), p_co => '{40}',
  p_ext => '[{"full_name":"Dr. Siriporn Wattanakul","institution":"Chulalongkorn University","country_code":"TH","role":"researcher"}]');

select pg_temp.h_act(234, 'Online Course Bahasa Jepang untuk Bisnis bersama Kyoto Sangyo University', 61, 79, 'inbound',
  '2026-02-16', '2026-05-29', 'online', 'Zoom Meeting', null, 27, '{4}',
  'Kursus daring 14 pertemuan bahasa Jepang bisnis yang diajar dosen mitra untuk mahasiswa lintas prodi.',
  pg_temp.h_wib('2026-06-08'), p_co => '{4}');

-- late: reported after the Genap 2025/2026 freeze (deadline 2026-07-26)
select pg_temp.h_act(235, 'Pengabdian Masyarakat Sanitasi Air Bersih bersama UGM', 55, 40, 'outbound',
  '2026-06-15', '2026-06-26', 'offline', 'Desa Ngargoyoso, Karanganyar', 'ID', 28, '{6,11}',
  'Pembangunan dan pelatihan perawatan sistem penyaringan air bersih skala desa bersama tim UGM.',
  pg_temp.h_wib('2026-09-02', '10:00'), p_co => '{20}');

-- ==== AY 2026/2027 Ganjil (to today) ================================================================================
-- ongoing semester exchange: draft, participants being prepared
select pg_temp.h_act(236, 'Inbound Exchange Yonsei University Semester Fall 2026', 5, 2, 'inbound',
  '2026-08-17', '2026-12-18', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,17}',
  'Mahasiswa pertukaran dari Korea mengikuti satu semester di Prodi Manajemen (kegiatan masih berjalan).',
  null, p_inb => '{X02260008,X02260015}', p_files => '{ia}');

select pg_temp.h_act(237, 'Kuliah Tamu Generative AI in Business dari National Taiwan University', 49, 15, 'inbound',
  '2026-09-28', '2026-09-29', 'hybrid', 'Gedung P PCU', 'ID', 52, '{4,9}',
  'Kuliah tamu pemanfaatan AI generatif dalam transformasi model bisnis untuk program Digital Business Transformation.',
  pg_temp.h_daysago(2, '10:00'),
  p_ext => '[{"full_name":"Prof. Lin Chia-Wei","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

-- in the Mobility queue
select pg_temp.h_act(238, 'Short Program Singapore Smart City di National University of Singapore', 28, 23, 'outbound',
  '2026-08-31', '2026-09-11', 'offline', 'National University of Singapore', 'SG', 36, '{9,11}',
  'Program singkat dua minggu tentang perencanaan kota cerdas, termasuk kunjungan ke Urban Redevelopment Authority.',
  pg_temp.h_daysago(12), 'pending', pg_temp.h_daysago(12),
  p_int => '{B11252003,B11256252,B11257273}', p_staff => '{PG190875}', p_co => '{68}');

select pg_temp.h_act(239, 'Riset Bersama Circular Economy Accounting dengan LMU Munich', 6, 4, 'outbound',
  '2026-09-01', '2026-09-25', 'online', 'Zoom Meeting', null, 42, '{12}',
  'Tahap awal riset pelaporan ekonomi sirkular: penyusunan instrumen dan pengumpulan data perusahaan terbuka.',
  pg_temp.h_daysago(5),
  p_ext => '[{"full_name":"Prof. Dr. Katharina Weber","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"researcher"}]');

-- on the Chulalongkorn renewal (34, successor of 29)
select pg_temp.h_act(240, 'Joint Seminar Southeast Asian Hospitality Trends', 8, 35, 'inbound',
  '2026-09-24', '2026-09-25', 'offline', 'Auditorium PCU', 'ID', 34, '{8}',
  'Seminar bersama tentang tren hospitaliti pascapandemi dan pariwisata berkelanjutan di Asia Tenggara.',
  pg_temp.h_daysago(3),
  p_ext => '[{"full_name":"Asst. Prof. Nattaya Chaiyaporn","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(241, 'Guest Lecture Pendidikan Inklusif dari Ateneo de Manila University', 73, 15, 'inbound',
  '2026-09-08', '2026-09-09', 'online', 'Zoom Meeting', null, 44, '{4,10}',
  'Kuliah tamu praktik pendidikan inklusif di sekolah dasar Filipina bagi mahasiswa PGSD.',
  pg_temp.h_daysago(20), p_co => '{36}',
  p_ext => '[{"full_name":"Dr. Maria Isabel Reyes","institution":"Ateneo de Manila University","country_code":"PH","role":"visiting_lecturer"}]');

-- Mobility asked for a revision three days ago
select pg_temp.h_act(242, 'Academic Exchange Program Keguruan di Ateneo de Manila University', 36, 28, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ateneo de Manila University, Quezon City', 'PH', 44, '{4}',
  'Mahasiswa PGSD mengikuti program pertukaran akademik empat minggu termasuk praktik mengajar di sekolah mitra.',
  pg_temp.h_daysago(6), 'revision_requested', pg_temp.h_daysago(3, '11:00'),
  p_mnote => 'Mohon unggah ulang PDF: dokumentasi kegiatan belum lengkap dan transkrip belum ada.',
  p_int => '{F51245128}', p_co => '{73}');

select pg_temp.h_act(243, 'Magang Industri Otomasi Kelistrikan di PT Astra International', 65, 21, 'outbound',
  '2026-08-03', '2026-09-25', 'offline', 'PT Astra International Tbk, Cikarang', 'ID', 23, '{8,9}',
  'Dua mahasiswa Teknik Elektro magang di divisi otomasi pabrik dengan proyek pemeliharaan prediktif.',
  pg_temp.h_daysago(7), 'approved', pg_temp.h_daysago(1, '14:00'),
  p_int => '{B12222426,B12223137}', p_staff => '{PG413450}');

select pg_temp.h_act(244, 'Pengabdian Masyarakat Kampung Tangguh Bencana bersama UGM', 20, 40, 'outbound',
  '2026-09-07', '2026-09-18', 'offline', 'Kabupaten Lumajang, Jawa Timur', 'ID', 40, '{11,13}',
  'Pelatihan mitigasi erupsi dan pemetaan jalur evakuasi partisipatif di tiga desa lereng Semeru.',
  pg_temp.h_daysago(8), p_co => '{35}');

select pg_temp.h_act(245, 'Workshop Design Thinking bersama University of Sydney', 63, 35, 'inbound',
  '2026-09-29', '2026-09-30', 'hybrid', 'Gedung P PCU', 'ID', 51, '{4,9}',
  'Lokakarya dua hari design thinking untuk mahasiswa DKV dan Desain Interior dengan fasilitator mitra.',
  pg_temp.h_daysago(1, '15:30'), p_co => '{59}',
  p_ext => '[{"full_name":"Dr. Olivia Grant","institution":"University of Sydney","country_code":"AU","role":"speaker"}]');

select pg_temp.h_act(246, 'Riset Bersama Water-Sensitive Urban Design Tahap II dengan University of Amsterdam', 54, 4, 'outbound',
  '2026-08-10', '2026-09-30', 'online', 'Microsoft Teams', null, 17, '{6,11}',
  'Lanjutan riset desain kota peka air: validasi model genangan dan lokakarya bersama pemangku kepentingan.',
  pg_temp.h_daysago(0, '08:30'), p_co => '{35}');

select pg_temp.h_act(247, 'Staff Exchange Pengelolaan Kantor Internasional ke National University of Singapore', 2, 31, 'outbound',
  '2026-09-14', '2026-09-18', 'offline', 'National University of Singapore, Global Relations Office', 'SG', 36, '{17}',
  'Staf KUI mempelajari tata kelola mobilitas mahasiswa dan sistem pelaporan kerja sama di kantor internasional mitra.',
  pg_temp.h_daysago(9));

-- in the Mobility queue
select pg_temp.h_act(248, 'Inbound Exchange Bisnis Asia Tenggara 2026', 4, 2, 'inbound',
  '2026-08-10', '2026-09-25', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,10}',
  'Mahasiswa pertukaran dari Thailand mengikuti modul bisnis Asia Tenggara selama tujuh minggu di SBM.',
  pg_temp.h_daysago(4), 'pending', pg_temp.h_daysago(4),
  p_inb => '{X01260068}');

-- future kegiatan: draft without files yet
select pg_temp.h_act(249, 'Kuliah Tamu Medical Education Innovation dari NUS', 76, 15, 'inbound',
  '2026-10-12', '2026-10-13', 'online', 'Zoom Meeting', null, 19, '{3,4}',
  'Kuliah tamu inovasi pendidikan kedokteran berbasis simulasi (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(250, 'Academic Visit Delegasi LMU Munich ke PCU', 28, 27, 'inbound',
  '2026-09-21', '2026-09-22', 'offline', 'Gedung T PCU', 'ID', 42, '{4,17}',
  'Kunjungan delegasi LMU untuk menindaklanjuti MoA: presentasi program, kunjungan laboratorium, dan diskusi pertukaran staf.',
  pg_temp.h_daysago(10), p_co => '{2}',
  p_ext => '[{"full_name":"Dr. Markus Hoffmann","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"staff_visitor"},{"full_name":"Julia Becker, M.A.","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"staff_visitor"}]');

select setval('realisasi.activity_code_seq', greatest(252, (select last_value from realisasi.activity_code_seq)));

-- No NRP claimed by two units on overlapping dates through these kegiatan (rule 2.1 would open a conflict)
do $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id <> a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.id between pg_temp.h_aid(201) and pg_temp.h_aid(252) and a.status <> 'draft'
     and x.nrp in (select realisasi._claimed_nrps(o.id));
  if v is not null then raise exception 'seeded kegiatan claim students of another unit on overlapping dates: %', v; end if;
end $$;

-- Snapshots (freezing AY 2024/2025, re-freezing stale ones) are handled in 06_participants.sql, after the participant
-- lists are complete.

-- >>> supabase/seed-supabase/06_participants.sql
-- seed-supabase/06_participants (simks-partnership): realistic Jumlah Peserta for the seeded mobility kegiatan, so
-- RENSTRA 1.1 (Jumlah mahasiswa Inbound & Outbound, R-38) and the International Awards boards have real numbers.
-- Written only into realisasi.*. Idempotent: every kegiatan is
-- filled UP TO a target size (a re-run adds nothing), snapshots are re-frozen only when stale.
--
-- 1. The student pool comes from 02b_registry_more.sql (mock BAAK + 735 PETRA / + 378 inbound students).
-- 2. Participants: each seeded mobility kegiatan (04: b5…, 05: c5…) gets students added to its CURRENT participant set
--    version until it reaches its target. Outbound kegiatan take PETRA students (section internal) from the submitting
--    unit's prodi, enrolled and at most in their 4th year (2nd for Magister) on the start date; inbound kegiatan take
--    exchange students (section inbound) whose home institution is the kegiatan's partner, same intake year. Staff and
--    external persons are not counted in RENSTRA 1.1 (R-19, R-20), so only a few staff companions are added.
--    A student is never picked when another unit claims them on overlapping dates (rule 2.1); the only conflict stays
--    the deliberate one from 04 (RL-2026-0006 / RL-2026-0013). Kegiatan not created by the seeds are never touched.
-- 3. Snapshots: AY 2024/2025 is frozen like the scheduled job would have (2025-03-02, 2025-08-30); any live system
--    snapshot that no longer matches what the job would have frozen (missing kegiatan or participants) is superseded by
--    a system re-freeze at its as-of time (+1 s so it is the latest). On a fresh deploy 90_freeze runs afterwards.

-- seed-supabase/lib/activity_helpers.inc: session-local (pg_temp) helpers shared by 05_activities_history,
-- 06_participants and 07_activities_more. Included with \ir; defines functions only, writes nothing.
--   h_act       one kegiatan with units, kerja sama, SDGs, external persons, files, participants and history
--   h_fill      add students (by prodi / partner, never across units on overlapping dates) up to a target size
--   h_assert_no_conflicts, h_refreeze_stale, h_date_freeze_notifications   checks and snapshot upkeep
-- Re-including is harmless (create or replace). No temp tables: a temp table that outlives its transaction stalls
-- Supabase's SQL API connection, so lookup data lives in functions.

create or replace function pg_temp.h_aid(n int) returns uuid language sql immutable as $$
  select ('c5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_gid(n int) returns uuid language sql immutable as $$
  select ('f5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.h_pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.h_wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null, p_frozen boolean default false)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.h_aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, p_frozen, p_at) $$;

-- the submitting account for a unit: SBM -> akun 3, Prodi Manajemen and its programs -> akun 4, else KUI (akun 1)
create or replace function pg_temp.h_creator(p_unit int) returns uuid language sql stable as $$
  select pg_temp.h_akun(case when p_unit = 4 then 3
                           when p_unit = 5 or exists (select 1 from kerjasama.units u where u.id = p_unit and u.parent_id = 5) then 4
                           else 1 end) $$;

-- which prodi a unit's outbound students come from (nearest mapped unit up the tree; a faculty takes all its prodi)
create or replace function pg_temp.h_unit_prodi() returns table(unit_id int, prodi text) language sql immutable as $$
  select * from (values
  (4, 'Manajemen'), (4, 'Akuntansi'), (4, 'International Business Management'), (4, 'Hotel Management'),
  (5, 'Manajemen'), (6, 'Akuntansi'), (7, 'International Business Management'), (8, 'Hotel Management'),
  (48, 'Magister Manajemen'), (51, 'Magister Manajemen'),
  (28, 'Informatika'), (28, 'Teknik Elektro'), (28, 'Teknik Industri'),
  (65, 'Teknik Elektro'), (67, 'Teknik Industri'), (68, 'Informatika'),
  (32, 'Desain Komunikasi Visual'), (32, 'Sastra Inggris'), (32, 'Ilmu Komunikasi'),
  (57, 'Ilmu Komunikasi'), (61, 'Sastra Inggris'), (63, 'Desain Komunikasi Visual'),
  (35, 'Arsitektur'), (35, 'Teknik Sipil'), (54, 'Arsitektur'), (55, 'Teknik Sipil'),
  (36, 'Pendidikan Guru Sekolah Dasar'), (73, 'Pendidikan Guru Sekolah Dasar'),
  (30, 'Kedokteran'), (76, 'Kedokteran'),
  (28, 'Teknik Mesin'), (69, 'Teknik Mesin'), (59, 'Desain Interior'), (60, 'Desain Interior'), (62, 'Desain Komunikasi Visual'),
  (58, 'Bahasa Mandarin'), (34, 'Kedokteran Gigi'), (74, 'Kedokteran Gigi'), (29, 'Magister Manajemen')) v(unit_id, prodi) $$;

create or replace function pg_temp.h_prodi_of(p_unit int) returns text[] language sql stable as $$
  with recursive up(id, parent_id, depth) as (
    select u.id, u.parent_id, 0 from kerjasama.units u where u.id = p_unit
    union all select u.id, u.parent_id, up.depth + 1 from kerjasama.units u join up on u.id = up.parent_id where up.depth < 5)
  select array_agg(m.prodi) from pg_temp.h_unit_prodi() m
   where m.unit_id = (select up.id from up where exists (select 1 from pg_temp.h_unit_prodi() x where x.unit_id = up.id)
                       order by up.depth limit 1) $$;

-- Add students to an activity's current participant set until it holds p_target counted students (+ staff up to
-- p_staff). Returns how many students were added.
create or replace function pg_temp.h_fill(p_activity uuid, p_target int, p_staff int default 0) returns int
language plpgsql as $$
declare a realisasi.activities; v_set uuid; v_section text; v_have int; v_need int; v_added int := 0;
        v_prodi text[]; v_partner text; v_ref int; v_years int;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not found then return 0; end if;
  select id into v_set from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  if v_set is null then raise exception 'activity %: no participant set', a.code; end if;
  v_section := case when a.direction = 'outbound' then 'internal' else 'inbound' end;
  select count(*) into v_have from realisasi.participant_students where set_version_id = v_set and section::text = v_section;
  v_need := p_target - v_have;

  -- academic intake that is enrolled on the start date (the AY starting in August)
  v_ref := extract(year from a.start_date)::int - case when extract(month from a.start_date) < 8 then 1 else 0 end;
  if v_section = 'internal' then
    v_prodi := pg_temp.h_prodi_of(a.submitter_unit_id);
    if v_prodi is null then raise exception 'activity %: no prodi mapping for unit %', a.code, a.submitter_unit_id; end if;
  else
    select p.name into v_partner from realisasi.activity_documents ad
      join kerjasama.document_partners dp on dp.document_id = ad.original_document_id and dp.is_lead
      join kerjasama.partners p on p.id = dp.partner_id
     where ad.activity_id = p_activity limit 1;
  end if;

  if v_need > 0 then
    with taken as (   -- students another unit claims on overlapping dates (any version, drafts included)
      select ps.nrp from realisasi.participant_students ps
        join realisasi.participant_set_versions v on v.id = ps.set_version_id
        join realisasi.activities o on o.id = v.activity_id
       where o.id <> a.id and o.submitter_unit_id <> a.submitter_unit_id
         and o.start_date <= a.end_date and a.start_date <= o.end_date),
    pick as (
      select s.* from mock_baak.students s
       where s.status <> 'inactive'
         and not exists (select 1 from realisasi.participant_students x where x.set_version_id = v_set and x.nrp = s.nrp)
         and s.nrp not in (select nrp from taken)
         and case when v_section = 'internal' then
                s.category = 'regular' and s.prodi_name = any(v_prodi)
                and s.intake_year <= v_ref
                and s.intake_year > v_ref - case when s.prodi_name = 'Magister Manajemen' then 2 else 4 end
                and s.intake_year < v_ref   -- no first-semester students abroad
              else
                s.category = 'inbound_exchange' and s.home_institution = v_partner
                and s.intake_year = extract(year from a.start_date)::int
              end
       order by exists (select 1 from realisasi.participant_students u where u.nrp = s.nrp), md5(s.nrp || a.code)
       limit v_need)
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_set, v_section::realisasi.student_section, p.nrp, p.full_name, p.faculty_name, p.prodi_name,
           p.home_institution, case when v_section = 'inbound' then 'HS-' || right(p.nrp, 4) end, p.home_country_code
      from pick p;
    get diagnostics v_added = row_count;
    if v_added < v_need then
      raise exception 'activity %: only % of % eligible students available', a.code, v_added, v_need;
    end if;
  end if;

  if p_staff > (select count(*) from realisasi.participant_staff where set_version_id = v_set) then
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e
     where e.status = 'active'
       and not exists (select 1 from realisasi.participant_staff x where x.set_version_id = v_set and x.employee_id = e.employee_id)
     order by md5(e.employee_id || a.code)
     limit p_staff - (select count(*) from realisasi.participant_staff where set_version_id = v_set);
  end if;
  return v_added;
end $$;

-- One kegiatan with its units, kerja sama, SDGs, external persons, files, participants (mobility) and history.
--   p_mstatus (mobility only): approved | pending | revision_requested; p_msince = when Mobility acted (or submit time)
--   p_rev: an earlier revision round {"note", "at", "resubmit"} before the final p_mstatus
--   p_auto / p_auto_staff: instead of listing NRPs, let pg_temp.h_fill pick that many students (and staff); with p_rev the
--   revised version 1 holds all but one of them (the student the revision note was about)
create or replace function pg_temp.h_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz,
  p_mstatus text default null, p_msince timestamptz default null, p_mnote text default null,
  p_int text[] default '{}', p_inb text[] default '{}', p_staff text[] default '{}',
  p_co int[] default '{}', p_ext jsonb default '[]', p_files text[] default '{ia,ir}', p_rev jsonb default null,
  p_auto int default 0, p_auto_staff int default 0)
returns void language plpgsql as $$
declare v_id uuid := pg_temp.h_aid(p_n); v_g uuid := pg_temp.h_gid(p_n);
        v_creator uuid := pg_temp.h_creator(p_unit); v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_verifier uuid := pg_temp.h_akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb; v_ver int := 1; v_pset uuid; v_status text;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'activity %: no account for unit %', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit) then raise exception 'activity %: SIMKS unit % missing', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'activity %: SIMKS agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'activity %: SIMKS document % not valid for % – %', p_n, p_doc, p_start, p_end;
  end if;
  if p_submitted is not null and p_end > (p_submitted at time zone 'Asia/Jakarta')::date then
    raise exception 'activity %: submitted before it ended (R-08)', p_n;
  end if;
  if v_mob and p_submitted is not null and ((cardinality(p_int) + cardinality(p_inb) = 0 and p_auto = 0) or p_mstatus is null) then
    raise exception 'activity %: a submitted mobility kegiatan needs students and a Mobility status', p_n;
  end if;

  -- drafts were opened a few days before the end date (never in the future); submissions three days before submitting
  v_created := case when p_submitted is not null then p_submitted - interval '3 days'
                    else least(pg_temp.h_wib(p_end) - interval '3 days', pg_temp.h_daysago(2)) end;
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');

  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then case when v_mob then p_msince else p_submitted end end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created,
          coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter)
  select v_id, p_unit, true union all select v_id, u, false from unnest(p_co) u where u <> p_unit;
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
    values (v_path, split_part(v_path, '/', 1), pg_temp.h_pdf(), 'application/pdf', length(pg_temp.h_pdf()), v_creator,
            v_created + interval '1 day')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.h_pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  -- participants (mobility only): an earlier revised version, then the current one (a draft set for a draft)
  if v_mob and cardinality(p_int) + cardinality(p_inb) + cardinality(p_staff) + p_auto > 0 then
    for v_ver in 1 .. case when p_rev is not null then 2 else 1 end loop
      v_pset := md5(v_id::text || ':v' || v_ver)::uuid;
      v_status := case when p_submitted is null then 'draft' when p_rev is not null and v_ver = 1 then 'revision_requested' else p_mstatus end;
      insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at,
                  reviewed_by, reviewed_at, review_note)
      values (v_pset, v_id, v_ver, v_status::realisasi.pset_status, case when p_submitted is not null then v_creator end,
              case when v_ver = 2 then (p_rev ->> 'resubmit')::timestamptz else p_submitted end,
              case when v_status in ('approved', 'revision_requested') then v_verifier end,
              case when p_rev is not null and v_ver = 1 then (p_rev ->> 'at')::timestamptz
                   when v_status in ('approved', 'revision_requested') then p_msince end,
              case when p_rev is not null and v_ver = 1 then p_rev ->> 'note' when v_status = 'revision_requested' then p_mnote end);
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
      select v_pset, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
        from unnest(p_int) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                  home_institution, home_student_number, home_country_code)
      select v_pset, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 4),
             s.home_country_code
        from unnest(p_inb) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
      select v_pset, e.employee_id, e.full_name, e.unit_name
        from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
    end loop;
    if p_auto = 0 and (select count(*) from realisasi.participant_students ps join realisasi.participant_set_versions v on v.id = ps.set_version_id
         where v.activity_id = v_id and v.version = 1) <> cardinality(p_int) + cardinality(p_inb) then
      raise exception 'activity %: an NRP is not in mock_baak.students', p_n;
    end if;
    if p_auto > 0 then
      perform pg_temp.h_fill(v_id, p_auto, p_auto_staff);
      if p_rev is not null then   -- version 1 (sent back) lacked the last student added in version 2
        insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                    home_institution, home_student_number, home_country_code)
        select md5(v_id::text || ':v1')::uuid, s.section, s.nrp, s.full_name, s.faculty_name, s.prodi_name,
               s.home_institution, s.home_student_number, s.home_country_code
          from realisasi.participant_students s where s.set_version_id = md5(v_id::text || ':v2')::uuid
         order by s.id limit greatest(p_auto - 1, 1)
        on conflict do nothing;
      end if;
    end if;
  end if;

  perform pg_temp.h_log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.h_log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if not v_mob then return; end if;
  if p_rev is not null then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, (p_rev ->> 'at')::timestamptz, p_rev ->> 'note');
    perform pg_temp.h_log(p_n, 'revision', 'mobility', 'resubmit', v_creator, (p_rev ->> 'resubmit')::timestamptz);
  end if;
  if p_mstatus = 'approved' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'approve', v_verifier, p_msince, null,
                        jsonb_build_object('version', case when p_rev is not null then 2 else 1 end));
  elsif p_mstatus = 'revision_requested' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, p_msince, p_mnote);
  end if;
end $$;

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
create or replace function pg_temp.h_assert_no_conflicts() returns void language plpgsql as $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id > a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.status <> 'draft' and x.nrp in (select realisasi._claimed_nrps(o.id))
     and not exists (select 1 from realisasi.participant_conflicts c
                      where c.nrp = x.nrp and c.activity_a = least(a.id, o.id) and c.activity_b = greatest(a.id, o.id));
  if v is not null then raise exception 'unintended student conflicts: %', v; end if;
end $$;

-- supersede system snapshots whose items differ from what the scheduled job would freeze now (oldest period first, so
-- later snapshots see the re-frozen previous period as their late-addition baseline)
-- (p_ay limits it to one academic year: on Supabase each re-freeze runs as its own short statement)
create or replace function pg_temp.h_refreeze_stale(p_reason text, p_ay int default null) returns int language plpgsql as $$
declare s realisasi.kpi_snapshots; n int := 0;
begin
  for s in select k.* from realisasi.kpi_snapshots k where k.superseded_by is null and k.frozen_by is null
                and (p_ay is null or k.academic_year_id = p_ay) order by k.frozen_at loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null, p_reason, s.id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- date system freezes' notifications (and outbox rows) at the snapshot's frozen_at, read for io_admin (as 90_freeze)
create or replace function pg_temp.h_date_freeze_notifications() returns void language sql as $$
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.frozen_by is null and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.frozen_by is null and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
$$;

-- 2. Participants ------------------------------------------------------------------------------------------------------
-- targets: counted students (outbound PETRA / inbound exchange) and staff companions per seeded mobility kegiatan,
-- in start-date order so earlier kegiatan choose first
select pg_temp.h_fill(t.id::uuid, t.target, t.staff)
  from (values
    -- AY 2024/2025
    ('c5000000-0000-4000-8000-000000000201',  4, 0),   -- Student Exchange Kyoto Sangyo (IBM)
    ('c5000000-0000-4000-8000-000000000204', 15, 2),   -- Cultural Exchange Youth Festival (DKV)
    ('c5000000-0000-4000-8000-000000000207', 20, 2),   -- Spring Japanese Short Program (SBM)
    ('c5000000-0000-4000-8000-000000000212',  3, 0),   -- Credit Transfer Kyoto Sangyo (IBM)
    ('c5000000-0000-4000-8000-000000000251',  9, 0),   -- Inbound Exchange from Kyoto Sangyo, Genap (SBM)
    ('c5000000-0000-4000-8000-000000000209',  6, 1),   -- Magang Kyoto (Informatika)
    ('c5000000-0000-4000-8000-000000000252', 14, 1),   -- Inbound Summer Program from Kyoto Sangyo (Hotel Management)
    -- AY 2025/2026
    ('b5000000-0000-4000-8000-000000000001',  6, 0),   -- RL-2026-0001 Student Exchange Kyoto Sangyo (SBM)
    ('c5000000-0000-4000-8000-000000000216', 10, 0),   -- Inbound Exchange from Kyoto Sangyo (SBM)
    ('c5000000-0000-4000-8000-000000000218',  4, 0),   -- Student Exchange Yonsei (Manajemen)
    ('c5000000-0000-4000-8000-000000000220', 16, 1),   -- Thai Hospitality Immersion (Hotel Management)
    ('c5000000-0000-4000-8000-000000000221',  8, 1),   -- Magang Astra (Teknik Industri)
    ('c5000000-0000-4000-8000-000000000225',  3, 0),   -- Double Degree NTU (Magister Manajemen)
    ('c5000000-0000-4000-8000-000000000228',  4, 0),   -- Student Exchange NUS (Informatika)
    ('c5000000-0000-4000-8000-000000000230', 24, 2),   -- Studi Ekskursi Kyoto-Osaka (Arsitektur)
    ('c5000000-0000-4000-8000-000000000231', 14, 1),   -- Bangkok Summer Business Camp (IBM)
    ('b5000000-0000-4000-8000-000000000006', 18, 2),   -- RL-2026-0006 Summer Program Chulalongkorn (SBM)
    ('b5000000-0000-4000-8000-000000000013',  6, 0),   -- RL-2026-0013 same program (Manajemen), in the queue
    -- AY 2026/2027
    ('c5000000-0000-4000-8000-000000000243',  5, 1),   -- Magang Astra (Teknik Elektro)
    ('b5000000-0000-4000-8000-000000000007',  8, 0),   -- RL-2026-0007 Inbound Exchange NUS (Manajemen)
    ('c5000000-0000-4000-8000-000000000248',  9, 0),   -- Inbound Exchange Chulalongkorn (SBM), in the queue
    ('c5000000-0000-4000-8000-000000000236',  8, 0),   -- Inbound Exchange Yonsei (Manajemen), draft
    ('c5000000-0000-4000-8000-000000000238', 20, 2),   -- Short Program NUS Smart City (FTI), in the queue
    ('c5000000-0000-4000-8000-000000000242',  6, 1),   -- Academic Exchange Ateneo (FKIP), revision requested
    ('b5000000-0000-4000-8000-000000000011',  5, 0)    -- RL-2026-0011 Student Exchange NUS (SBM), in the queue
  ) t(id, target, staff)
 where exists (select 1 from realisasi.activities a where a.id = t.id::uuid);

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
select pg_temp.h_assert_no_conflicts();

-- 3. Snapshots ---------------------------------------------------------------------------------------------------------
select realisasi.freeze_snapshot(3, 'ganjil_ytd', '2025-03-02 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'ganjil_ytd' and superseded_by is null);
select realisasi.freeze_snapshot(3, 'genap_full_year', '2025-08-30 01:00+07')
 where exists (select 1 from realisasi.academic_years where id = 3)
   and not exists (select 1 from realisasi.kpi_snapshots where academic_year_id = 3 and kind = 'genap_full_year' and superseded_by is null);

-- supersede system snapshots whose items differ from what the scheduled job would freeze now
select pg_temp.h_refreeze_stale('Data historis kegiatan dan peserta ditambahkan (seed).');
select pg_temp.h_date_freeze_notifications();

-- >>> supabase/seed-supabase/07_activities_more.sql
-- seed-supabase/07_activities_more (simks-partnership): 100 more kegiatan (RL-xxxx-0301 … 0400) from AY 2024/2025 to
-- today, on REAL SIMKS documents, written only into realisasi.*. Idempotent: an existing activity is skipped, participant
-- lists are filled up to their target, snapshots are re-frozen only when stale.
--   22 in AY 2024/2025 (all on document 11, the only agreement valid before 2025-10-17), 50 in AY 2025/2026, 28 in
--   AY 2026/2027 up to today; 35 mobility kegiatan (student exchange, credit transfer, double degree, short/summer,
--   immersion, cultural exchange, magang, studi ekskursi, academic exchange) and 65 others (kuliah tamu, joint research,
--   COIL joint lectures, seminars, workshops, pelatihan, academic visits, staff exchange, pengabdian, rekrutmen).
--   ~45 units incl. FKG, Kedokteran, FKIP, LPPM, BPM, ELTC, CIRD, Perpustakaan, PPMG; co-units; external persons
--   named for the agreement's partner.
--   States: verified (on submit, or approved by Mobility; two after a revision round), late reports and late additions
--   after a freeze, three in the Mobility queue, one revision still open, ongoing semester exchanges and planned events
--   as drafts, two abandoned drafts.
--   Participants are picked by pg_temp.h_fill (p_auto): prodi of the submitting unit / students of the partner, intake
--   that fits the dates, never claimed by another unit on overlapping dates.
-- Generated from a reviewed table of 100 rows: every row's dates were checked against its document's validity, R-08
-- (submitted after the end date) and the Mobility timeline before writing; h_act re-checks R-04 against live SIMKS.
-- Ids: activities c5000000-0000-4000-8000-0000000003NN, event groups f5000000-…; codes RL-<year created>-03NN.

-- seed-supabase/lib/activity_helpers.inc: session-local (pg_temp) helpers shared by 05_activities_history,
-- 06_participants and 07_activities_more. Included with \ir; defines functions only, writes nothing.
--   h_act       one kegiatan with units, kerja sama, SDGs, external persons, files, participants and history
--   h_fill      add students (by prodi / partner, never across units on overlapping dates) up to a target size
--   h_assert_no_conflicts, h_refreeze_stale, h_date_freeze_notifications   checks and snapshot upkeep
-- Re-including is harmless (create or replace). No temp tables: a temp table that outlives its transaction stalls
-- Supabase's SQL API connection, so lookup data lives in functions.

create or replace function pg_temp.h_aid(n int) returns uuid language sql immutable as $$
  select ('c5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_gid(n int) returns uuid language sql immutable as $$
  select ('f5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.h_akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.h_pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.h_wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_daysago(n int, t time default '09:00') returns timestamptz language sql stable as $$
  select ((realisasi.today() - n) + t) at time zone 'Asia/Jakarta' $$;
create or replace function pg_temp.h_log(p_n int, p_kind text, p_track text, p_action text, p_actor uuid, p_at timestamptz,
                                       p_note text default null, p_diff jsonb default null, p_frozen boolean default false)
returns void language sql as $$
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (pg_temp.h_aid(p_n), p_kind::realisasi.log_kind, p_track::realisasi.team, p_action, p_actor, p_note, p_diff, p_frozen, p_at) $$;

-- the submitting account for a unit: SBM -> akun 3, Prodi Manajemen and its programs -> akun 4, else KUI (akun 1)
create or replace function pg_temp.h_creator(p_unit int) returns uuid language sql stable as $$
  select pg_temp.h_akun(case when p_unit = 4 then 3
                           when p_unit = 5 or exists (select 1 from kerjasama.units u where u.id = p_unit and u.parent_id = 5) then 4
                           else 1 end) $$;

-- which prodi a unit's outbound students come from (nearest mapped unit up the tree; a faculty takes all its prodi)
create or replace function pg_temp.h_unit_prodi() returns table(unit_id int, prodi text) language sql immutable as $$
  select * from (values
  (4, 'Manajemen'), (4, 'Akuntansi'), (4, 'International Business Management'), (4, 'Hotel Management'),
  (5, 'Manajemen'), (6, 'Akuntansi'), (7, 'International Business Management'), (8, 'Hotel Management'),
  (48, 'Magister Manajemen'), (51, 'Magister Manajemen'),
  (28, 'Informatika'), (28, 'Teknik Elektro'), (28, 'Teknik Industri'),
  (65, 'Teknik Elektro'), (67, 'Teknik Industri'), (68, 'Informatika'),
  (32, 'Desain Komunikasi Visual'), (32, 'Sastra Inggris'), (32, 'Ilmu Komunikasi'),
  (57, 'Ilmu Komunikasi'), (61, 'Sastra Inggris'), (63, 'Desain Komunikasi Visual'),
  (35, 'Arsitektur'), (35, 'Teknik Sipil'), (54, 'Arsitektur'), (55, 'Teknik Sipil'),
  (36, 'Pendidikan Guru Sekolah Dasar'), (73, 'Pendidikan Guru Sekolah Dasar'),
  (30, 'Kedokteran'), (76, 'Kedokteran'),
  (28, 'Teknik Mesin'), (69, 'Teknik Mesin'), (59, 'Desain Interior'), (60, 'Desain Interior'), (62, 'Desain Komunikasi Visual'),
  (58, 'Bahasa Mandarin'), (34, 'Kedokteran Gigi'), (74, 'Kedokteran Gigi'), (29, 'Magister Manajemen')) v(unit_id, prodi) $$;

create or replace function pg_temp.h_prodi_of(p_unit int) returns text[] language sql stable as $$
  with recursive up(id, parent_id, depth) as (
    select u.id, u.parent_id, 0 from kerjasama.units u where u.id = p_unit
    union all select u.id, u.parent_id, up.depth + 1 from kerjasama.units u join up on u.id = up.parent_id where up.depth < 5)
  select array_agg(m.prodi) from pg_temp.h_unit_prodi() m
   where m.unit_id = (select up.id from up where exists (select 1 from pg_temp.h_unit_prodi() x where x.unit_id = up.id)
                       order by up.depth limit 1) $$;

-- Add students to an activity's current participant set until it holds p_target counted students (+ staff up to
-- p_staff). Returns how many students were added.
create or replace function pg_temp.h_fill(p_activity uuid, p_target int, p_staff int default 0) returns int
language plpgsql as $$
declare a realisasi.activities; v_set uuid; v_section text; v_have int; v_need int; v_added int := 0;
        v_prodi text[]; v_partner text; v_ref int; v_years int;
begin
  select * into a from realisasi.activities where id = p_activity;
  if not found then return 0; end if;
  select id into v_set from realisasi.participant_set_versions where activity_id = p_activity order by version desc limit 1;
  if v_set is null then raise exception 'activity %: no participant set', a.code; end if;
  v_section := case when a.direction = 'outbound' then 'internal' else 'inbound' end;
  select count(*) into v_have from realisasi.participant_students where set_version_id = v_set and section::text = v_section;
  v_need := p_target - v_have;

  -- academic intake that is enrolled on the start date (the AY starting in August)
  v_ref := extract(year from a.start_date)::int - case when extract(month from a.start_date) < 8 then 1 else 0 end;
  if v_section = 'internal' then
    v_prodi := pg_temp.h_prodi_of(a.submitter_unit_id);
    if v_prodi is null then raise exception 'activity %: no prodi mapping for unit %', a.code, a.submitter_unit_id; end if;
  else
    select p.name into v_partner from realisasi.activity_documents ad
      join kerjasama.document_partners dp on dp.document_id = ad.original_document_id and dp.is_lead
      join kerjasama.partners p on p.id = dp.partner_id
     where ad.activity_id = p_activity limit 1;
  end if;

  if v_need > 0 then
    with taken as (   -- students another unit claims on overlapping dates (any version, drafts included)
      select ps.nrp from realisasi.participant_students ps
        join realisasi.participant_set_versions v on v.id = ps.set_version_id
        join realisasi.activities o on o.id = v.activity_id
       where o.id <> a.id and o.submitter_unit_id <> a.submitter_unit_id
         and o.start_date <= a.end_date and a.start_date <= o.end_date),
    pick as (
      select s.* from mock_baak.students s
       where s.status <> 'inactive'
         and not exists (select 1 from realisasi.participant_students x where x.set_version_id = v_set and x.nrp = s.nrp)
         and s.nrp not in (select nrp from taken)
         and case when v_section = 'internal' then
                s.category = 'regular' and s.prodi_name = any(v_prodi)
                and s.intake_year <= v_ref
                and s.intake_year > v_ref - case when s.prodi_name = 'Magister Manajemen' then 2 else 4 end
                and s.intake_year < v_ref   -- no first-semester students abroad
              else
                s.category = 'inbound_exchange' and s.home_institution = v_partner
                and s.intake_year = extract(year from a.start_date)::int
              end
       order by exists (select 1 from realisasi.participant_students u where u.nrp = s.nrp), md5(s.nrp || a.code)
       limit v_need)
    insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                home_institution, home_student_number, home_country_code)
    select v_set, v_section::realisasi.student_section, p.nrp, p.full_name, p.faculty_name, p.prodi_name,
           p.home_institution, case when v_section = 'inbound' then 'HS-' || right(p.nrp, 4) end, p.home_country_code
      from pick p;
    get diagnostics v_added = row_count;
    if v_added < v_need then
      raise exception 'activity %: only % of % eligible students available', a.code, v_added, v_need;
    end if;
  end if;

  if p_staff > (select count(*) from realisasi.participant_staff where set_version_id = v_set) then
    insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
    select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e
     where e.status = 'active'
       and not exists (select 1 from realisasi.participant_staff x where x.set_version_id = v_set and x.employee_id = e.employee_id)
     order by md5(e.employee_id || a.code)
     limit p_staff - (select count(*) from realisasi.participant_staff where set_version_id = v_set);
  end if;
  return v_added;
end $$;

-- One kegiatan with its units, kerja sama, SDGs, external persons, files, participants (mobility) and history.
--   p_mstatus (mobility only): approved | pending | revision_requested; p_msince = when Mobility acted (or submit time)
--   p_rev: an earlier revision round {"note", "at", "resubmit"} before the final p_mstatus
--   p_auto / p_auto_staff: instead of listing NRPs, let pg_temp.h_fill pick that many students (and staff); with p_rev the
--   revised version 1 holds all but one of them (the student the revision note was about)
create or replace function pg_temp.h_act(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_desc text, p_submitted timestamptz,
  p_mstatus text default null, p_msince timestamptz default null, p_mnote text default null,
  p_int text[] default '{}', p_inb text[] default '{}', p_staff text[] default '{}',
  p_co int[] default '{}', p_ext jsonb default '[]', p_files text[] default '{ia,ir}', p_rev jsonb default null,
  p_auto int default 0, p_auto_staff int default 0)
returns void language plpgsql as $$
declare v_id uuid := pg_temp.h_aid(p_n); v_g uuid := pg_temp.h_gid(p_n);
        v_creator uuid := pg_temp.h_creator(p_unit); v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_verifier uuid := pg_temp.h_akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb; v_ver int := 1; v_pset uuid; v_status text;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if v_creator is null then raise exception 'activity %: no account for unit %', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit) then raise exception 'activity %: SIMKS unit % missing', p_n, p_unit; end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'activity %: SIMKS agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'activity %: SIMKS document % not valid for % – %', p_n, p_doc, p_start, p_end;
  end if;
  if p_submitted is not null and p_end > (p_submitted at time zone 'Asia/Jakarta')::date then
    raise exception 'activity %: submitted before it ended (R-08)', p_n;
  end if;
  if v_mob and p_submitted is not null and ((cardinality(p_int) + cardinality(p_inb) = 0 and p_auto = 0) or p_mstatus is null) then
    raise exception 'activity %: a submitted mobility kegiatan needs students and a Mobility status', p_n;
  end if;

  -- drafts were opened a few days before the end date (never in the future); submissions three days before submitting
  v_created := case when p_submitted is not null then p_submitted - interval '3 days'
                    else least(pg_temp.h_wib(p_end) - interval '3 days', pg_temp.h_daysago(2)) end;
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');

  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 60 then 20 else 3 end end,
          p_desc, p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then case when v_mob then p_msince else p_submitted end end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created,
          coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter)
  select v_id, p_unit, true union all select v_id, u, false from unnest(p_co) u where u <> p_unit;
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
    values (v_path, split_part(v_path, '/', 1), pg_temp.h_pdf(), 'application/pdf', length(pg_temp.h_pdf()), v_creator,
            v_created + interval '1 day')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.h_pdf()), 'application/pdf', true, v_creator, v_created + interval '1 day');
  end loop;

  -- participants (mobility only): an earlier revised version, then the current one (a draft set for a draft)
  if v_mob and cardinality(p_int) + cardinality(p_inb) + cardinality(p_staff) + p_auto > 0 then
    for v_ver in 1 .. case when p_rev is not null then 2 else 1 end loop
      v_pset := md5(v_id::text || ':v' || v_ver)::uuid;
      v_status := case when p_submitted is null then 'draft' when p_rev is not null and v_ver = 1 then 'revision_requested' else p_mstatus end;
      insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at,
                  reviewed_by, reviewed_at, review_note)
      values (v_pset, v_id, v_ver, v_status::realisasi.pset_status, case when p_submitted is not null then v_creator end,
              case when v_ver = 2 then (p_rev ->> 'resubmit')::timestamptz else p_submitted end,
              case when v_status in ('approved', 'revision_requested') then v_verifier end,
              case when p_rev is not null and v_ver = 1 then (p_rev ->> 'at')::timestamptz
                   when v_status in ('approved', 'revision_requested') then p_msince end,
              case when p_rev is not null and v_ver = 1 then p_rev ->> 'note' when v_status = 'revision_requested' then p_mnote end);
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
      select v_pset, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
        from unnest(p_int) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                  home_institution, home_student_number, home_country_code)
      select v_pset, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 4),
             s.home_country_code
        from unnest(p_inb) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
      insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
      select v_pset, e.employee_id, e.full_name, e.unit_name
        from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
    end loop;
    if p_auto = 0 and (select count(*) from realisasi.participant_students ps join realisasi.participant_set_versions v on v.id = ps.set_version_id
         where v.activity_id = v_id and v.version = 1) <> cardinality(p_int) + cardinality(p_inb) then
      raise exception 'activity %: an NRP is not in mock_baak.students', p_n;
    end if;
    if p_auto > 0 then
      perform pg_temp.h_fill(v_id, p_auto, p_auto_staff);
      if p_rev is not null then   -- version 1 (sent back) lacked the last student added in version 2
        insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
                    home_institution, home_student_number, home_country_code)
        select md5(v_id::text || ':v1')::uuid, s.section, s.nrp, s.full_name, s.faculty_name, s.prodi_name,
               s.home_institution, s.home_student_number, s.home_country_code
          from realisasi.participant_students s where s.set_version_id = md5(v_id::text || ':v2')::uuid
         order by s.id limit greatest(p_auto - 1, 1)
        on conflict do nothing;
      end if;
    end if;
  end if;

  perform pg_temp.h_log(p_n, 'system', null, 'create', v_creator, v_created);
  if p_submitted is null then return; end if;
  perform pg_temp.h_log(p_n, 'system', null, 'submit', v_creator, p_submitted);
  if not v_mob then return; end if;
  if p_rev is not null then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, (p_rev ->> 'at')::timestamptz, p_rev ->> 'note');
    perform pg_temp.h_log(p_n, 'revision', 'mobility', 'resubmit', v_creator, (p_rev ->> 'resubmit')::timestamptz);
  end if;
  if p_mstatus = 'approved' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'approve', v_verifier, p_msince, null,
                        jsonb_build_object('version', case when p_rev is not null then 2 else 1 end));
  elsif p_mstatus = 'revision_requested' then
    perform pg_temp.h_log(p_n, 'verification', 'mobility', 'request_revision', v_verifier, p_msince, p_mnote);
  end if;
end $$;

-- the only student conflicts are the ones the seeds create on purpose (04: RL-2026-0006 / RL-2026-0013)
create or replace function pg_temp.h_assert_no_conflicts() returns void language plpgsql as $$
declare v text;
begin
  select string_agg(distinct x.nrp || ' (' || a.code || ' / ' || o.code || ')', ', ') into v
    from realisasi.activities a
    join realisasi.activities o on o.id > a.id and o.status <> 'draft' and o.submitter_unit_id <> a.submitter_unit_id
                               and o.start_date <= a.end_date and a.start_date <= o.end_date
    cross join lateral (select realisasi._claimed_nrps(a.id) as nrp) x
   where a.status <> 'draft' and x.nrp in (select realisasi._claimed_nrps(o.id))
     and not exists (select 1 from realisasi.participant_conflicts c
                      where c.nrp = x.nrp and c.activity_a = least(a.id, o.id) and c.activity_b = greatest(a.id, o.id));
  if v is not null then raise exception 'unintended student conflicts: %', v; end if;
end $$;

-- supersede system snapshots whose items differ from what the scheduled job would freeze now (oldest period first, so
-- later snapshots see the re-frozen previous period as their late-addition baseline)
-- (p_ay limits it to one academic year: on Supabase each re-freeze runs as its own short statement)
create or replace function pg_temp.h_refreeze_stale(p_reason text, p_ay int default null) returns int language plpgsql as $$
declare s realisasi.kpi_snapshots; n int := 0;
begin
  for s in select k.* from realisasi.kpi_snapshots k where k.superseded_by is null and k.frozen_by is null
                and (p_ay is null or k.academic_year_id = p_ay) order by k.frozen_at loop
    if exists ((select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i
                except
                select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id)
               union all
               (select i.kpi_code, i.bucket, i.ref_type, i.ref_id from realisasi.kpi_snapshot_items i where i.snapshot_id = s.id
                except
                select distinct i.kpi_code, i.bucket, i.ref_type, i.ref_id
                  from realisasi.kpi_items(s.window_start, s.window_end, s.cutoff_date, s.academic_year_id, s.frozen_at, null) i)) then
      perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at + interval '1 second', null, p_reason, s.id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- date system freezes' notifications (and outbox rows) at the snapshot's frozen_at, read for io_admin (as 90_freeze)
create or replace function pg_temp.h_date_freeze_notifications() returns void language sql as $$
update realisasi.notifications n
   set created_at = k.frozen_at,
       read_at = case when p.app_role = 'io_admin' then k.frozen_at + interval '1 day' end
  from realisasi.kpi_snapshots k, kerjasama.profiles p
 where n.kind = 'snapshot_frozen' and n.link = '/realisasi/laporan?report=arsip&snapshot=' || k.id
   and p.id = n.recipient_id and k.frozen_by is null and n.created_at is distinct from k.frozen_at;
update realisasi.email_outbox o set created_at = k.frozen_at
  from realisasi.kpi_snapshots k
 where k.frozen_by is null and o.body like '%/realisasi/laporan?report=arsip&snapshot=' || k.id
   and o.created_at is distinct from k.frozen_at;
$$;

do $$
declare d int;
begin
  foreach d in array array[11, 12, 15, 17, 19, 21, 23, 25, 27, 28, 29, 30, 31, 32, 33, 36, 38, 42, 44, 51] loop
    if not exists (select 1 from kerjasama.documents where id = d and status not in ('in_process', 'rejected') and start_date is not null) then
      raise exception 'SIMKS document % missing or not selectable; adjust supabase/seed-supabase/07_activities_more.sql', d;
    end if;
  end loop;
end $$;

-- ==== AY 2024/2025 (document 11 is the only agreement valid before 2025-10-17) =================================
select pg_temp.h_act(301, 'Academic Visit Delegasi Kyoto Sangyo University ke PCU', 2, 27, 'inbound',
  '2024-08-26', '2024-08-27', 'offline', 'Gedung W PCU', 'ID', 11, '{4,17}',
  'Kunjungan pimpinan Kyoto Sangyo University untuk meluncurkan rencana implementasi MoU: pertukaran mahasiswa, riset bersama, dan kelas kolaboratif.',
  pg_temp.h_wib('2024-09-02', '09:00'), p_ext => '[{"full_name":"Prof. Masaru Ikeda","institution":"Kyoto Sangyo University","country_code":"JP","role":"staff_visitor"},{"full_name":"Naoko Fujita, M.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"staff_visitor"}]');

select pg_temp.h_act(302, 'Riset Bersama Perilaku Wisatawan Jepang di Bali', 46, 4, 'outbound',
  '2024-09-02', '2025-01-24', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Survei dan wawancara wisatawan Jepang di Bali untuk merumuskan strategi pariwisata kreatif berbasis komunitas.',
  pg_temp.h_wib('2025-02-02', '09:00'), p_ext => '[{"full_name":"Dr. Kenji Watanabe","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(303, 'Kuliah Tamu Manajemen Rantai Pasok Industri Otomotif Jepang', 67, 15, 'inbound',
  '2024-09-18', '2024-09-18', 'offline', 'Gedung T PCU', 'ID', 11, '{9,12}',
  'Kuliah tamu praktik just-in-time dan kaizen pada pemasok otomotif Jepang untuk mahasiswa Teknik Industri.',
  pg_temp.h_wib('2024-09-23', '09:00'), p_ext => '[{"full_name":"Prof. Takuya Ono","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(304, 'Short Program Autumn Japanese Design and Culture di Kyoto Sangyo University', 59, 23, 'outbound',
  '2024-10-07', '2024-10-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,11}',
  'Program dua minggu tentang desain ruang tradisional Jepang, kunjungan kuil dan machiya, serta studio desain bersama mahasiswa mitra.',
  pg_temp.h_wib('2024-10-26', '09:00'), 'approved', pg_temp.h_wib('2024-11-02', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(305, 'Workshop Desain Kemasan Produk UMKM bersama Kyoto Sangyo University', 63, 35, 'inbound',
  '2024-10-23', '2024-10-24', 'hybrid', 'Lab DKV Gedung P PCU', 'ID', 11, '{8,9,12}',
  'Lokakarya desain kemasan ramah lingkungan untuk 25 UMKM binaan, difasilitasi dosen mitra dan mahasiswa DKV.',
  pg_temp.h_wib('2024-10-28', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Rie Kobayashi","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(306, 'Student Exchange Semester Ganjil 2024 Teknik Industri di Kyoto Sangyo University', 67, 2, 'outbound',
  '2024-09-16', '2025-01-24', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Mahasiswa Teknik Industri mengikuti satu semester perkuliahan sistem produksi dan ergonomi di Faculty of Science and Engineering.',
  pg_temp.h_wib('2025-02-03', '09:00'), 'approved', pg_temp.h_wib('2025-02-11', '14:00'), p_auto => 3);

select pg_temp.h_act(307, 'Seminar Internasional Pendidikan Karakter di Asia Timur', 36, 35, 'inbound',
  '2024-11-06', '2024-11-06', 'hybrid', 'Auditorium PCU', 'ID', 11, '{4,16}',
  'Seminar perbandingan pendidikan karakter di sekolah Jepang dan Indonesia bagi guru mitra dan mahasiswa FKIP.',
  pg_temp.h_wib('2024-11-13', '09:00'), p_ext => '[{"full_name":"Prof. Hiroko Saito","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(308, 'Kuliah Tamu Bahasa Jepang untuk Perhotelan', 8, 15, 'inbound',
  '2024-11-19', '2024-11-21', 'offline', 'Hotel Laboratorium PCU', 'ID', 11, '{4,8}',
  'Tiga sesi bahasa Jepang layanan tamu (omotenashi) untuk mahasiswa Hotel Management.',
  pg_temp.h_wib('2024-11-27', '09:00'), p_ext => '[{"full_name":"Yumi Takeda, M.Ed.","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(309, 'Riset Bersama Smart Grid Kampus Hijau dengan Kyoto Sangyo University', 65, 4, 'inbound',
  '2024-12-02', '2025-01-31', 'hybrid', 'Lab Sistem Tenaga PCU', 'ID', 11, '{7,13}',
  'Pemodelan beban listrik kampus dan simulasi integrasi panel surya atap; peneliti mitra berkunjung satu minggu.',
  pg_temp.h_wib('2025-02-12', '09:00'), p_ext => '[{"full_name":"Dr. Shinji Hayashi","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(310, 'Webinar Kesehatan Mental Mahasiswa Internasional', 30, 35, 'inbound',
  '2025-01-15', '2025-01-15', 'online', 'Zoom Meeting', null, 11, '{3}',
  'Webinar strategi dukungan kesehatan mental bagi mahasiswa pertukaran; dilaporkan terlambat.',
  pg_temp.h_wib('2025-02-24', '09:00'), p_ext => '[{"full_name":"Dr. Ayaka Mori","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(311, 'Studi Ekskursi Bisnis Kuliner ke Kyoto dan Osaka', 41, 24, 'outbound',
  '2025-01-13', '2025-01-22', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{2,8,12}',
  'Kunjungan pasar Nishiki, dapur pusat restoran, dan kelas manajemen kuliner di Kyoto Sangyo University.',
  pg_temp.h_wib('2025-01-31', '09:00'), 'approved', pg_temp.h_wib('2025-02-06', '14:00'), p_auto => 18, p_auto_staff => 2);

select pg_temp.h_act(312, 'Inbound Short Program Batik and Javanese Culture 2025', 60, 29, 'inbound',
  '2025-02-17', '2025-02-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 11, '{4,11}',
  'Mahasiswa Kyoto Sangyo University belajar membatik, tata busana tradisional, dan budaya Jawa Timur selama dua minggu.',
  pg_temp.h_wib('2025-03-07', '09:00'), 'approved', pg_temp.h_wib('2025-03-13', '14:00'), p_auto => 12);

select pg_temp.h_act(313, 'Joint Lecture Pemasaran Digital Lintas Negara (COIL)', 42, 34, 'inbound',
  '2025-02-24', '2025-05-30', 'online', 'Zoom Meeting', null, 11, '{4,17}',
  'Kelas kolaboratif daring 12 pertemuan; mahasiswa PCU dan Kyoto Sangyo menyusun kampanye pemasaran untuk produk lokal.',
  pg_temp.h_wib('2025-06-07', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Daisuke Matsumoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(314, 'Credit Transfer Informatika di Kyoto Sangyo University', 68, 33, 'outbound',
  '2025-04-01', '2025-07-25', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Mahasiswa Informatika mengambil mata kuliah kecerdasan buatan dan sistem terdistribusi yang diakui penuh di PCU.',
  pg_temp.h_wib('2025-08-01', '09:00'), 'approved', pg_temp.h_wib('2025-08-10', '14:00'), p_auto => 3);

select pg_temp.h_act(315, 'Pengabdian Masyarakat Pemetaan Risiko Banjir bersama Mahasiswa Kyoto Sangyo', 55, 40, 'outbound',
  '2025-03-10', '2025-03-21', 'offline', 'Kelurahan Kebraon, Surabaya', 'ID', 11, '{11,13}',
  'Pemetaan partisipatif titik genangan dan jalur evakuasi bersama warga, mahasiswa Teknik Sipil, dan mahasiswa mitra.',
  pg_temp.h_wib('2025-03-31', '09:00'), p_co => '{20}');

select pg_temp.h_act(316, 'Kuliah Tamu Etika Bisnis Jepang untuk Akuntan', 44, 15, 'inbound',
  '2025-03-12', '2025-03-12', 'offline', 'Gedung P PCU', 'ID', 11, '{8,16}',
  'Kuliah tamu tata kelola perusahaan dan etika profesi akuntan di Jepang.',
  pg_temp.h_wib('2025-03-17', '09:00'), p_ext => '[{"full_name":"Prof. Ichiro Nakagawa","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(317, 'Lomba Desain Poster Internasional PCU–Kyoto Sangyo 2025', 63, 35, 'inbound',
  '2025-04-14', '2025-05-16', 'hybrid', 'Galeri DKV PCU', 'ID', 11, '{4,17}',
  'Kompetisi poster bertema keberlanjutan dengan 140 karya dari mahasiswa kedua universitas dan pameran hasil.',
  pg_temp.h_wib('2025-05-28', '09:00'), p_co => '{32}');

select pg_temp.h_act(318, 'Staff Exchange Pengelolaan Perpustakaan Digital ke Kyoto Sangyo University', 24, 31, 'outbound',
  '2025-04-21', '2025-04-25', 'offline', 'Kyoto Sangyo University Library', 'JP', 11, '{4,16}',
  'Pustakawan PCU mempelajari layanan repositori digital dan literasi informasi di perpustakaan mitra.',
  pg_temp.h_wib('2025-05-13', '09:00'));

select pg_temp.h_act(319, 'Summer Program Japanese Technology and Society di Kyoto Sangyo University', 28, 23, 'outbound',
  '2025-06-30', '2025-07-18', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,9}',
  'Program musim panas tiga minggu: robotika, kota cerdas, kunjungan pabrik di Kansai, dan proyek tim lintas negara.',
  pg_temp.h_wib('2025-07-23', '09:00'), 'approved', pg_temp.h_wib('2025-08-03', '14:00'), p_rev => jsonb_build_object('note', 'Transkrip satu peserta belum ada di PDF gabungan; mohon lengkapi dan ajukan ulang.', 'at', pg_temp.h_wib('2025-07-27', '10:00'), 'resubmit', pg_temp.h_wib('2025-07-31', '15:00')), p_auto => 22, p_auto_staff => 2);

select pg_temp.h_act(320, 'Riset Bersama Pengajaran Bahasa Inggris Berbasis Proyek', 61, 4, 'outbound',
  '2025-02-03', '2025-06-27', 'online', 'Microsoft Teams', null, 11, '{4}',
  'Studi kelas pembelajaran berbasis proyek di dua universitas; dilaporkan terlambat.',
  pg_temp.h_wib('2025-08-24', '09:00'));

select pg_temp.h_act(321, 'Magang Hospitality di Hotel Mitra Kyoto', 8, 21, 'outbound',
  '2025-05-05', '2025-07-25', 'offline', 'Hotel mitra Kyoto Sangyo University, Kyoto', 'JP', 11, '{8}',
  'Magang dua belas minggu di departemen front office dan F&B hotel mitra di Kyoto.',
  pg_temp.h_wib('2025-07-31', '09:00'), 'approved', pg_temp.h_wib('2025-08-08', '14:00'), p_auto => 6);

select pg_temp.h_act(322, 'Seminar Kebijakan Pariwisata Berkelanjutan Jepang–Indonesia', 46, 35, 'inbound',
  '2025-06-18', '2025-06-18', 'online', 'Zoom Meeting', null, 11, '{8,11}',
  'Seminar daring kebijakan pariwisata berkelanjutan (draf tidak dilanjutkan).',
  null, p_files => '{ia}');

-- ==== AY 2025/2026 Ganjil ===========================================================================================
select pg_temp.h_act(323, 'Kuliah Tamu Animasi dan Industri Kreatif Jepang', 62, 15, 'inbound',
  '2025-08-27', '2025-08-28', 'hybrid', 'Gedung P PCU', 'ID', 11, '{4,8,9}',
  'Dua sesi tentang alur produksi anime dan peluang kerja industri kreatif bagi mahasiswa International Program in Digital Media.',
  pg_temp.h_wib('2025-09-03', '09:00'), p_ext => '[{"full_name":"Takashi Endo, M.F.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(324, 'Student Exchange Semester Ganjil 2025 Desain Interior di Kyoto Sangyo University', 59, 2, 'outbound',
  '2025-09-15', '2026-01-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,11}',
  'Mahasiswa Desain Interior mengikuti satu semester studio desain dan sejarah arsitektur Jepang.',
  pg_temp.h_wib('2026-02-01', '09:00'), 'approved', pg_temp.h_wib('2026-02-08', '14:00'), p_auto => 2);

select pg_temp.h_act(325, 'Riset Bersama Material Bangunan Rendah Karbon', 54, 4, 'inbound',
  '2025-09-01', '2025-12-19', 'hybrid', 'Lab Struktur dan Material PCU', 'ID', 11, '{9,11,13}',
  'Uji karakteristik bata dan panel berbahan limbah pertanian untuk rumah tropis; peneliti mitra berkunjung dua minggu.',
  pg_temp.h_wib('2025-12-30', '09:00'), p_co => '{55}', p_ext => '[{"full_name":"Dr. Hideo Kimura","institution":"Kyoto Sangyo University","country_code":"JP","role":"researcher"}]');

select pg_temp.h_act(326, 'Workshop Penulisan Proposal Hibah Internasional', 20, 43, 'inbound',
  '2025-09-24', '2025-09-25', 'offline', 'Ruang Seminar LPPM PCU', 'ID', 11, '{4,17}',
  'Lokakarya dua hari penyusunan proposal hibah riset internasional untuk 40 dosen.',
  pg_temp.h_wib('2025-09-30', '09:00'), p_ext => '[{"full_name":"Prof. Yoshiko Arai","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(327, 'Seminar Nasional Ekonomi Kreatif bersama UGM', 4, 35, 'inbound',
  '2025-10-22', '2025-10-22', 'offline', 'Auditorium PCU', 'ID', 28, '{8}',
  'Seminar nasional peran ekonomi kreatif dalam pertumbuhan daerah dengan 300 peserta.',
  pg_temp.h_wib('2025-10-28', '09:00'), p_ext => '[{"full_name":"Dr. Rina Kartikasari","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(328, 'Riset Bersama Kesehatan Masyarakat Pesisir dengan UGM', 76, 4, 'outbound',
  '2025-11-03', '2026-02-27', 'hybrid', 'Puskesmas Kenjeran dan Zoom', 'ID', 28, '{3,14}',
  'Studi status gizi dan kesehatan lingkungan keluarga nelayan di pesisir Kenjeran bersama peneliti UGM.',
  pg_temp.h_wib('2026-03-09', '09:00'));

select pg_temp.h_act(329, 'Kuliah Tamu Hukum Bisnis Thailand', 43, 15, 'inbound',
  '2025-10-29', '2025-10-29', 'online', 'Zoom Meeting', null, 29, '{8,16}',
  'Kuliah tamu regulasi investasi dan perdagangan Thailand untuk program International Trade and Finance.',
  pg_temp.h_wib('2025-11-02', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Pongsak Thongchai","institution":"Chulalongkorn University","country_code":"TH","role":"visiting_lecturer"}]');

select pg_temp.h_act(330, 'Academic Visit Prodi Teknik Mesin ke National Taiwan University', 69, 27, 'outbound',
  '2025-11-10', '2025-11-14', 'offline', 'National Taiwan University, Taipei', 'TW', 30, '{9}',
  'Kunjungan laboratorium manufaktur presisi dan penjajakan program magang riset mahasiswa Teknik Mesin.',
  pg_temp.h_wib('2025-11-21', '09:00'), p_co => '{28}');

select pg_temp.h_act(331, 'Student Exchange Akuntansi di Yonsei University Semester Spring 2026', 6, 2, 'outbound',
  '2026-02-23', '2026-06-19', 'offline', 'Yonsei University, Sinchon Campus', 'KR', 31, '{4}',
  'Mahasiswa Akuntansi mengikuti Spring Semester di Yonsei School of Business.',
  pg_temp.h_wib('2026-06-28', '09:00'), 'approved', pg_temp.h_wib('2026-07-06', '14:00'), p_auto => 3);

select pg_temp.h_act(332, 'Winter Immersion K-Culture di Yonsei University', 57, 22, 'outbound',
  '2026-01-05', '2026-01-16', 'offline', 'Yonsei University', 'KR', 31, '{4,10}',
  'Program imersi dua minggu tentang media dan budaya populer Korea bagi mahasiswa Ilmu Komunikasi.',
  pg_temp.h_wib('2026-01-22', '09:00'), 'approved', pg_temp.h_wib('2026-01-31', '14:00'), p_auto => 14, p_auto_staff => 1);

select pg_temp.h_act(333, 'Joint Webinar Circular Fashion bersama University of Amsterdam', 60, 35, 'inbound',
  '2025-11-26', '2025-11-26', 'online', 'Zoom Meeting', null, 32, '{12}',
  'Webinar mode sirkular dan daur ulang tekstil untuk mahasiswa Textile and Fashion Design.',
  pg_temp.h_wib('2025-12-01', '09:00'), p_ext => '[{"full_name":"Dr. Lotte Visser","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(334, 'Inbound Exchange Semester Ganjil dari National Taiwan University', 28, 2, 'inbound',
  '2025-10-20', '2026-01-16', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,9}',
  'Mahasiswa NTU mengikuti perkuliahan teknik berbahasa Inggris dan proyek lab di FTI.',
  pg_temp.h_wib('2026-01-24', '09:00'), 'approved', pg_temp.h_wib('2026-01-30', '14:00'), p_auto => 6);

select pg_temp.h_act(335, 'Pelatihan Lean Six Sigma bersama PT Astra International', 67, 69, 'inbound',
  '2025-12-09', '2025-12-11', 'offline', 'Lab Sistem Industri PCU', 'ID', 12, '{8,9}',
  'Pelatihan sabuk kuning Lean Six Sigma untuk 45 mahasiswa tingkat akhir oleh praktisi Astra.',
  pg_temp.h_wib('2025-12-16', '09:00'), p_ext => '[{"full_name":"Ir. Hendro Saputro, M.T.","institution":"PT Astra International Tbk","country_code":"ID","role":"other"}]');

select pg_temp.h_act(336, 'Pengabdian Masyarakat Gizi Anak bersama UGM', 76, 40, 'outbound',
  '2025-12-01', '2025-12-12', 'offline', 'Kabupaten Sidoarjo', 'ID', 28, '{2,3}',
  'Skrining gizi balita dan edukasi menu sehat bagi kader posyandu di empat desa.',
  pg_temp.h_wib('2025-12-20', '09:00'), p_co => '{20}');

select pg_temp.h_act(337, 'Seminar Internasional Akuntansi Keberlanjutan ASEAN', 6, 35, 'inbound',
  '2025-11-19', '2025-11-20', 'hybrid', 'Auditorium PCU', 'ID', 29, '{12,13}',
  'Seminar pelaporan keberlanjutan dan standar ISSB di ASEAN dengan pembicara Chulalongkorn.',
  pg_temp.h_wib('2025-11-29', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Kanokwan Rattanakul","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(338, 'Rekrutmen Management Trainee bersama PT Astra International', 18, 39, 'inbound',
  '2025-12-15', '2025-12-16', 'offline', 'Gedung W PCU', 'ID', 12, '{8}',
  'Presentasi perusahaan, tes, dan wawancara program management trainee bagi lulusan PCU.',
  pg_temp.h_wib('2025-12-20', '09:00'));

select pg_temp.h_act(339, 'Kuliah Tamu Arsitektur Tropis Asia dari National Taiwan University', 53, 15, 'inbound',
  '2026-01-14', '2026-01-15', 'offline', 'Gedung P PCU', 'ID', 30, '{11,13}',
  'Kuliah tamu desain pasif bangunan tropis untuk mahasiswa Magister Arsitektur.',
  pg_temp.h_wib('2026-01-22', '09:00'), p_ext => '[{"full_name":"Prof. Huang Shu-fen","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.h_act(340, 'Magang Data Analytics di PT Astra International', 68, 21, 'outbound',
  '2026-01-05', '2026-02-27', 'offline', 'PT Astra International Tbk, Jakarta', 'ID', 12, '{8,9}',
  'Mahasiswa Informatika magang delapan minggu membangun dasbor analitik penjualan.',
  pg_temp.h_wib('2026-03-05', '09:00'), 'approved', pg_temp.h_wib('2026-03-12', '14:00'), p_auto => 5);

select pg_temp.h_act(341, 'Riset Bersama Kebijakan Fiskal Daerah dengan UGM', 43, 4, 'outbound',
  '2025-10-27', '2026-01-30', 'online', 'Zoom Meeting', null, 28, '{8,16}',
  'Analisis efektivitas transfer dana desa; dilaporkan setelah batas Ganjil (penambahan terlambat).',
  pg_temp.h_wib('2026-03-16', '09:00'));

select pg_temp.h_act(342, 'Student Exchange Semester Ganjil 2025 Sastra Inggris di Kyoto Sangyo University', 61, 2, 'outbound',
  '2025-09-22', '2026-01-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4}',
  'Mahasiswa Sastra Inggris mengikuti program studi bahasa dan budaya di Faculty of Foreign Studies.',
  pg_temp.h_wib('2026-02-02', '09:00'), 'approved', pg_temp.h_wib('2026-02-08', '14:00'), p_auto => 2);

select pg_temp.h_act(343, 'Kuliah Tamu Teknologi Pangan Fungsional', 41, 15, 'inbound',
  '2025-09-10', '2025-09-10', 'offline', 'Lab Kuliner PCU', 'ID', 11, '{2,3}',
  'Kuliah tamu pengembangan produk pangan fungsional untuk program Culinary Business Management.',
  pg_temp.h_wib('2025-09-15', '09:00'), p_ext => '[{"full_name":"Dr. Mayumi Ishikawa","institution":"Kyoto Sangyo University","country_code":"JP","role":"visiting_lecturer"}]');

select pg_temp.h_act(344, 'Workshop Kepemimpinan Mahasiswa Asia', 23, 43, 'inbound',
  '2025-10-01', '2025-10-03', 'offline', 'Gedung W PCU', 'ID', 11, '{4,16}',
  'Pelatihan kepemimpinan dan kerja lintas budaya untuk 60 pengurus organisasi mahasiswa.',
  pg_temp.h_wib('2025-10-09', '09:00'), p_ext => '[{"full_name":"Sota Yamamoto, M.A.","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2025/2026 Genap ============================================================================================
select pg_temp.h_act(345, 'Short Program Spring Business di National University of Singapore', 45, 23, 'outbound',
  '2026-03-02', '2026-03-13', 'offline', 'National University of Singapore', 'SG', 19, '{4,8}',
  'Program dua minggu keuangan dan investasi Asia, kunjungan SGX dan perusahaan fintech.',
  pg_temp.h_wib('2026-03-19', '09:00'), 'approved', pg_temp.h_wib('2026-03-27', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(346, 'Inbound Exchange Semester Genap dari Chulalongkorn University', 4, 2, 'inbound',
  '2026-02-23', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 25, '{4,17}',
  'Mahasiswa Chulalongkorn mengikuti satu semester di SBM dengan program buddy dan kelas bahasa Indonesia.',
  pg_temp.h_wib('2026-07-03', '09:00'), 'approved', pg_temp.h_wib('2026-07-09', '14:00'), p_auto => 7);

select pg_temp.h_act(347, 'Riset Bersama Air Bersih Perkotaan dengan University of Amsterdam', 56, 4, 'outbound',
  '2026-03-02', '2026-06-30', 'online', 'Microsoft Teams', null, 17, '{6,11}',
  'Pemodelan kebocoran jaringan air kota dan skenario pengurangan air tak berekening.',
  pg_temp.h_wib('2026-07-12', '09:00'), p_ext => '[{"full_name":"Dr. Thijs Mulder","institution":"University of Amsterdam","country_code":"NL","role":"researcher"}]');

select pg_temp.h_act(348, 'Seminar Internasional Hospitality Asia Tenggara 2026', 8, 35, 'inbound',
  '2026-03-18', '2026-03-19', 'offline', 'Auditorium PCU', 'ID', 25, '{8,17}',
  'Seminar dan kompetisi studi kasus hospitaliti dengan 12 kampus dari Asia Tenggara.',
  pg_temp.h_wib('2026-03-25', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Warut Phromma","institution":"Chulalongkorn University","country_code":"TH","role":"speaker"}]');

select pg_temp.h_act(349, 'Double Degree Teknik Elektro dengan National Taiwan University', 65, 17, 'outbound',
  '2026-02-23', '2026-07-17', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,9}',
  'Mahasiswa Teknik Elektro menempuh semester pertama program gelar ganda di NTU.',
  pg_temp.h_wib('2026-07-24', '09:00'), 'approved', pg_temp.h_wib('2026-07-30', '14:00'), p_auto => 2);

select pg_temp.h_act(350, 'Kuliah Tamu Kewirausahaan Sosial dari Unilever Indonesia', 50, 15, 'inbound',
  '2026-03-25', '2026-03-25', 'offline', 'Gedung P PCU', 'ID', 21, '{8,12}',
  'Kuliah tamu model bisnis sosial dan program pemberdayaan UMKM perusahaan.',
  pg_temp.h_wib('2026-03-30', '09:00'), p_ext => '[{"full_name":"Dewi Anggraini, M.B.A.","institution":"PT Unilever Indonesia Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(351, 'Magang Supply Chain di PT Unilever Indonesia', 67, 21, 'outbound',
  '2026-03-02', '2026-05-29', 'offline', 'PT Unilever Indonesia Tbk, Rungkut Surabaya', 'ID', 21, '{8,12}',
  'Magang tiga bulan di perencanaan produksi dan logistik pabrik Rungkut.',
  pg_temp.h_wib('2026-06-04', '09:00'), 'approved', pg_temp.h_wib('2026-06-11', '14:00'), p_auto => 6, p_auto_staff => 1);

select pg_temp.h_act(352, 'Studi Ekskursi Arsitektur Tropis ke Singapura', 53, 24, 'outbound',
  '2026-04-06', '2026-04-11', 'offline', 'National University of Singapore', 'SG', 19, '{11}',
  'Studi lapangan bangunan hijau dan perencanaan kota di Singapura bersama School of Design and Environment NUS.',
  pg_temp.h_wib('2026-04-16', '09:00'), 'approved', pg_temp.h_wib('2026-04-22', '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(353, 'Joint Lecture Machine Learning (COIL) bersama National Taiwan University', 68, 34, 'inbound',
  '2026-02-23', '2026-05-29', 'online', 'Microsoft Teams', null, 15, '{4,9}',
  'Kelas kolaboratif daring pembelajaran mesin; tim campuran mengerjakan proyek data kesehatan.',
  pg_temp.h_wib('2026-06-06', '09:00'), p_ext => '[{"full_name":"Asst. Prof. Chen Po-han","institution":"National Taiwan University","country_code":"TW","role":"visiting_lecturer"}]');

select pg_temp.h_act(354, 'Pengabdian Masyarakat Literasi Keuangan Pekerja Migran bersama UGM', 40, 40, 'outbound',
  '2026-04-13', '2026-04-24', 'offline', 'Kabupaten Ponorogo', 'ID', 28, '{1,8,10}',
  'Pelatihan pengelolaan remitansi dan pencegahan penipuan keuangan bagi keluarga pekerja migran.',
  pg_temp.h_wib('2026-05-03', '09:00'), p_co => '{20}');

select pg_temp.h_act(355, 'Riset Bersama Material Gigi Biokompatibel dengan Chulalongkorn University', 74, 4, 'inbound',
  '2026-03-09', '2026-06-26', 'hybrid', 'Lab Biomaterial FKG PCU', 'ID', 25, '{3,9}',
  'Uji sitotoksisitas bahan tambal gigi berbasis nano-hidroksiapatit; peneliti mitra berkunjung dua minggu.',
  pg_temp.h_wib('2026-07-06', '09:00'), p_ext => '[{"full_name":"Dr. Chayanin Boonmee","institution":"Chulalongkorn University","country_code":"TH","role":"researcher"}]');

select pg_temp.h_act(356, 'Student Exchange Semester Genap Hotel Management di Chulalongkorn University', 8, 2, 'outbound',
  '2026-02-23', '2026-06-12', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8}',
  'Mahasiswa Hotel Management mengikuti satu semester di Faculty of Commerce and Accountancy.',
  pg_temp.h_wib('2026-06-20', '09:00'), 'approved', pg_temp.h_wib('2026-06-27', '14:00'), p_auto => 3);

select pg_temp.h_act(357, 'Webinar Internasional Pendidikan Anak Usia Dini', 72, 35, 'inbound',
  '2026-04-22', '2026-04-22', 'online', 'Zoom Meeting', null, 17, '{4,5}',
  'Webinar pembelajaran berbasis bermain dan kesetaraan gender di PAUD.',
  pg_temp.h_wib('2026-04-28', '09:00'), p_ext => '[{"full_name":"Dr. Emma de Jong","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(358, 'Summer Program Engineering Innovation di National Taiwan University', 69, 23, 'outbound',
  '2026-07-06', '2026-07-24', 'offline', 'National Taiwan University', 'TW', 15, '{9}',
  'Program musim panas tiga minggu desain produk dan manufaktur aditif.',
  pg_temp.h_wib('2026-07-31', '09:00'), 'approved', pg_temp.h_wib('2026-08-08', '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(359, 'Inbound Short Program Indonesian Language and Culture 2026', 32, 29, 'inbound',
  '2026-07-13', '2026-07-24', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,10}',
  'Mahasiswa Yonsei belajar bahasa Indonesia, gamelan, dan kuliner Jawa Timur selama dua minggu.',
  pg_temp.h_wib('2026-07-30', '09:00'), 'approved', pg_temp.h_wib('2026-08-05', '14:00'), p_auto => 12);

select pg_temp.h_act(360, 'Academic Visit Delegasi Chulalongkorn University ke Fakultas Kedokteran Gigi', 34, 27, 'inbound',
  '2026-05-11', '2026-05-12', 'offline', 'Gedung FKG PCU', 'ID', 25, '{3,17}',
  'Kunjungan dekanat mitra untuk merancang pertukaran klinis dan riset biomaterial.',
  pg_temp.h_wib('2026-05-17', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Siriporn Kaewkla","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"},{"full_name":"Dr. Thanawat Srisuk","institution":"Chulalongkorn University","country_code":"TH","role":"staff_visitor"}]');

select pg_temp.h_act(361, 'Seminar Nasional Teknologi Otomotif bersama PT Astra International', 69, 35, 'inbound',
  '2026-05-20', '2026-05-20', 'offline', 'Auditorium PCU', 'ID', 23, '{9}',
  'Seminar kendaraan listrik dan rantai pasok baterai dengan praktisi industri.',
  pg_temp.h_wib('2026-05-25', '09:00'), p_ext => '[{"full_name":"Ir. Agus Wibisono","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(362, 'Kuliah Tamu Perpajakan Internasional dari National University of Singapore', 47, 15, 'inbound',
  '2026-04-15', '2026-04-15', 'online', 'Zoom Meeting', null, 19, '{8,16}',
  'Kuliah tamu pajak lintas batas dan BEPS untuk program Tax Accounting.',
  pg_temp.h_wib('2026-04-19', '09:00'), p_ext => '[{"full_name":"Dr. Arjun Nair","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(363, 'Staff Exchange Penjaminan Mutu ke Chulalongkorn University', 15, 31, 'outbound',
  '2026-05-25', '2026-05-29', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,16}',
  'Staf Badan Penjaminan Mutu mempelajari sistem akreditasi internasional di mitra.',
  pg_temp.h_wib('2026-06-06', '09:00'));

select pg_temp.h_act(364, 'Student Exchange Ilmu Komunikasi di University of Amsterdam', 57, 2, 'outbound',
  '2026-02-02', '2026-06-26', 'offline', 'University of Amsterdam', 'NL', 32, '{4}',
  'Mahasiswa Ilmu Komunikasi mengikuti semester di Graduate School of Communication.',
  pg_temp.h_wib('2026-07-05', '09:00'), 'approved', pg_temp.h_wib('2026-07-18', '14:00'), p_rev => jsonb_build_object('note', 'Learning agreement belum ditandatangani mitra; mohon unggah ulang PDF.', 'at', pg_temp.h_wib('2026-07-10', '10:00'), 'resubmit', pg_temp.h_wib('2026-07-14', '15:00')), p_auto => 2);

select pg_temp.h_act(365, 'Workshop Pembelajaran Berbasis Proyek bersama Kyoto Sangyo University', 17, 43, 'inbound',
  '2026-02-25', '2026-02-26', 'offline', 'Gedung T PCU', 'ID', 27, '{4}',
  'Lokakarya desain mata kuliah berbasis proyek untuk 50 dosen lintas fakultas.',
  pg_temp.h_wib('2026-03-03', '09:00'), p_ext => '[{"full_name":"Prof. Kaito Yamamoto","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

select pg_temp.h_act(366, 'Riset Bersama Pemasaran Pariwisata Halal dengan Chulalongkorn University', 46, 4, 'outbound',
  '2026-03-02', '2026-06-30', 'online', 'Zoom Meeting', null, 25, '{8}',
  'Studi preferensi wisatawan muslim di Thailand dan Indonesia; dilaporkan setelah batas Genap (penambahan terlambat).',
  pg_temp.h_wib('2026-09-08', '09:00'));

select pg_temp.h_act(367, 'Konser Kolaborasi Musik Gerejawi Thailand–Indonesia', 21, 35, 'inbound',
  '2026-05-29', '2026-05-29', 'offline', 'Auditorium PCU', 'ID', 25, '{4,10}',
  'Konser dan lokakarya paduan suara bersama musisi Chulalongkorn.',
  pg_temp.h_wib('2026-06-04', '09:00'), p_ext => '[{"full_name":"Napat Saengthong","institution":"Chulalongkorn University","country_code":"TH","role":"other"}]');

select pg_temp.h_act(368, 'Kuliah Tamu Manajemen Rumah Sakit dari National University of Singapore', 30, 15, 'inbound',
  '2026-06-03', '2026-06-03', 'hybrid', 'Gedung Fakultas Kedokteran PCU', 'ID', 19, '{3}',
  'Kuliah tamu mutu layanan dan keselamatan pasien di rumah sakit pendidikan.',
  pg_temp.h_wib('2026-06-08', '09:00'), p_ext => '[{"full_name":"Assoc. Prof. Goh Hui Min","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(369, 'Workshop Ekspor UMKM bersama PT Astra International', 43, 35, 'inbound',
  '2026-06-17', '2026-06-17', 'offline', 'Gedung P PCU', 'ID', 23, '{8}',
  'Lokakarya kesiapan ekspor UMKM binaan (draf belum diajukan).',
  null, p_files => '{ia}');

select pg_temp.h_act(370, 'Summer Program Sustainable Cities di University of Amsterdam', 35, 23, 'outbound',
  '2026-07-06', '2026-07-17', 'offline', 'University of Amsterdam', 'NL', 17, '{11,13}',
  'Program musim panas dua minggu perencanaan kota berkelanjutan dan pengelolaan air di Amsterdam.',
  pg_temp.h_wib('2026-07-25', '09:00'), 'approved', pg_temp.h_wib('2026-07-31', '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(371, 'Riset Bersama AI untuk Diagnosis Medis dengan National Taiwan University', 68, 4, 'outbound',
  '2026-03-16', '2026-07-31', 'online', 'Microsoft Teams', null, 15, '{3,9}',
  'Pengembangan model deteksi retinopati diabetik dari citra fundus bersama peneliti NTU.',
  pg_temp.h_wib('2026-08-10', '09:00'), p_co => '{76}');

select pg_temp.h_act(372, 'Pelatihan Guru Bahasa Inggris Sekolah Mitra', 73, 63, 'inbound',
  '2026-06-22', '2026-06-26', 'offline', 'Gedung T PCU', 'ID', 27, '{4}',
  'Pelatihan lima hari metode komunikatif untuk 35 guru SD mitra, difasilitasi dosen Kyoto Sangyo.',
  pg_temp.h_wib('2026-07-02', '09:00'), p_ext => '[{"full_name":"Yui Kato, M.Ed.","institution":"Kyoto Sangyo University","country_code":"JP","role":"speaker"}]');

-- ==== AY 2026/2027 Ganjil (to today) ================================================================================
select pg_temp.h_act(373, 'Inbound Exchange Semester Ganjil 2026 dari National Taiwan University', 28, 2, 'inbound',
  '2026-08-24', '2026-12-18', 'offline', 'Kampus PCU Siwalankerto', 'ID', 30, '{4,9}',
  'Mahasiswa NTU mengikuti semester di FTI (kegiatan masih berjalan).',
  null, p_auto => 6, p_files => '{ia}');

select pg_temp.h_act(374, 'Student Exchange Semester Fall 2026 di Yonsei University', 4, 2, 'outbound',
  '2026-08-31', '2026-12-18', 'offline', 'Yonsei University', 'KR', 31, '{4}',
  'Mahasiswa SBM mengikuti Fall Semester di Yonsei (kegiatan masih berjalan).',
  null, p_auto => 3, p_files => '{ia}');

select pg_temp.h_act(375, 'Kuliah Tamu Smart Logistics dari LMU Munich', 67, 15, 'inbound',
  '2026-09-02', '2026-09-02', 'offline', 'Gedung T PCU', 'ID', 42, '{9}',
  'Kuliah tamu digitalisasi logistik dan rantai pasok di Eropa.',
  pg_temp.h_daysago(26, '09:00'), p_ext => '[{"full_name":"Prof. Dr. Jonas Wagner","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"visiting_lecturer"}]');

select pg_temp.h_act(376, 'Short Program Sustainable Business di Chulalongkorn University', 49, 23, 'outbound',
  '2026-08-03', '2026-08-14', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8}',
  'Program dua minggu transformasi digital bisnis berkelanjutan di Sasin School of Management.',
  pg_temp.h_daysago(40, '09:00'), 'approved', pg_temp.h_daysago(33, '14:00'), p_auto => 10, p_auto_staff => 1);

select pg_temp.h_act(377, 'Magang Riset Energi Terbarukan di LMU Munich', 65, 21, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ludwig Maximilian University of Munich', 'DE', 42, '{7,9}',
  'Magang riset empat minggu di laboratorium fotovoltaik mitra.',
  pg_temp.h_daysago(5, '09:00'), 'pending', pg_temp.h_daysago(5, '09:00'), p_auto => 2);

select pg_temp.h_act(378, 'Seminar Internasional Pendidikan Inklusif ASEAN', 36, 35, 'inbound',
  '2026-09-16', '2026-09-17', 'hybrid', 'Auditorium PCU', 'ID', 44, '{4,10}',
  'Seminar praktik baik sekolah inklusif di Filipina dan Indonesia.',
  pg_temp.h_daysago(12, '09:00'), p_ext => '[{"full_name":"Dr. Bianca Torres","institution":"Ateneo de Manila University","country_code":"PH","role":"speaker"}]');

select pg_temp.h_act(379, 'Riset Bersama Diaspora dan Identitas Budaya dengan Ateneo de Manila University', 61, 4, 'outbound',
  '2026-09-01', '2026-09-30', 'online', 'Zoom Meeting', null, 44, '{10,16}',
  'Tahap awal riset narasi diaspora Filipina dan Indonesia: desain instrumen dan wawancara pilot.',
  pg_temp.h_daysago(2, '09:00'));

select pg_temp.h_act(380, 'Inbound Short Program Southeast Asian Business 2026 dari NUS', 5, 23, 'inbound',
  '2026-08-17', '2026-08-28', 'offline', 'Kampus PCU Siwalankerto', 'ID', 19, '{4,17}',
  'Mahasiswa NUS mengikuti program dua minggu bisnis keluarga dan UMKM Jawa Timur.',
  pg_temp.h_daysago(30, '09:00'), 'approved', pg_temp.h_daysago(24, '14:00'), p_auto => 10);

select pg_temp.h_act(381, 'Academic Visit Delegasi University of Sydney ke PCU', 2, 27, 'inbound',
  '2026-09-28', '2026-09-28', 'offline', 'Gedung W PCU', 'ID', 51, '{4,17}',
  'Kunjungan untuk menindaklanjuti MoU: penjajakan program bersama dan beasiswa.',
  pg_temp.h_daysago(3, '09:00'), p_ext => '[{"full_name":"Prof. Charlotte Wilson","institution":"University of Sydney","country_code":"AU","role":"staff_visitor"},{"full_name":"Jack Taylor, M.Ed.","institution":"University of Sydney","country_code":"AU","role":"staff_visitor"}]');

select pg_temp.h_act(382, 'Kuliah Tamu Digital Health dari University of Sydney', 76, 15, 'inbound',
  '2026-09-30', '2026-09-30', 'online', 'Zoom Meeting', null, 51, '{3}',
  'Kuliah tamu telemedisin dan rekam medis elektronik.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Olivia Brown","institution":"University of Sydney","country_code":"AU","role":"visiting_lecturer"}]');

select pg_temp.h_act(383, 'Workshop Tata Kelola Data Riset bersama UGM', 20, 43, 'inbound',
  '2026-09-23', '2026-09-24', 'offline', 'Ruang Seminar LPPM PCU', 'ID', 33, '{9,16}',
  'Lokakarya rencana pengelolaan data riset dan repositori terbuka.',
  pg_temp.h_daysago(6, '09:00'), p_ext => '[{"full_name":"Dr. Bayu Pratama","institution":"Universitas Gadjah Mada","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(384, 'Pengabdian Masyarakat Sekolah Siaga Bencana bersama UGM', 72, 40, 'outbound',
  '2026-08-17', '2026-08-28', 'offline', 'Kabupaten Malang', 'ID', 28, '{4,11,13}',
  'Simulasi evakuasi dan modul kesiapsiagaan bencana untuk 12 PAUD dan SD.',
  pg_temp.h_daysago(28, '09:00'));

select pg_temp.h_act(385, 'Academic Exchange Klinik Kedokteran Gigi di Chulalongkorn University', 74, 28, 'outbound',
  '2026-08-24', '2026-09-18', 'offline', 'Chulalongkorn University', 'TH', 25, '{3,4}',
  'Mahasiswa Kedokteran Gigi mengikuti rotasi klinik empat minggu di Faculty of Dentistry.',
  pg_temp.h_daysago(9, '09:00'), 'revision_requested', pg_temp.h_daysago(4, '11:00'), p_mnote => 'Surat keterangan klinik mitra dan transkrip belum ada di PDF; mohon unggah ulang.', p_auto => 3);

select pg_temp.h_act(386, 'Short Program Manufacturing 4.0 di National Taiwan University', 66, 23, 'outbound',
  '2026-08-17', '2026-08-28', 'offline', 'National Taiwan University', 'TW', 15, '{9}',
  'Program dua minggu pabrik cerdas dan otomasi untuk International Business Engineering.',
  pg_temp.h_daysago(25, '09:00'), 'approved', pg_temp.h_daysago(18, '14:00'), p_auto => 12, p_auto_staff => 1);

select pg_temp.h_act(387, 'Magang Desain Interior di Studio Mitra Bangkok', 59, 21, 'outbound',
  '2026-08-03', '2026-09-25', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 38, '{9,11}',
  'Magang delapan minggu di studio desain mitra Chulalongkorn.',
  pg_temp.h_daysago(6, '09:00'), 'pending', pg_temp.h_daysago(6, '09:00'), p_auto => 3);

select pg_temp.h_act(388, 'Seminar Nasional Keuangan Berkelanjutan bersama PT Astra International', 45, 35, 'inbound',
  '2026-09-09', '2026-09-09', 'offline', 'Auditorium PCU', 'ID', 23, '{8,13}',
  'Seminar pembiayaan hijau dan pelaporan emisi perusahaan.',
  pg_temp.h_daysago(18, '09:00'), p_ext => '[{"full_name":"Rina Hapsari, CFA","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(389, 'Kuliah Tamu Hukum Kesehatan Internasional dari NUS', 30, 15, 'inbound',
  '2026-09-14', '2026-09-14', 'online', 'Zoom Meeting', null, 36, '{3,16}',
  'Kuliah tamu etika dan regulasi kesehatan global.',
  pg_temp.h_daysago(15, '09:00'), p_ext => '[{"full_name":"Prof. Marcus Ong","institution":"National University of Singapore","country_code":"SG","role":"visiting_lecturer"}]');

select pg_temp.h_act(390, 'Joint Webinar Water Governance bersama University of Amsterdam', 55, 35, 'inbound',
  '2026-09-10', '2026-09-10', 'online', 'Zoom Meeting', null, 17, '{6}',
  'Webinar tata kelola air perkotaan di delta Belanda dan Surabaya.',
  pg_temp.h_daysago(20, '09:00'), p_ext => '[{"full_name":"Dr. Daan Bakker","institution":"University of Amsterdam","country_code":"NL","role":"speaker"}]');

select pg_temp.h_act(391, 'Credit Transfer Semester Ganjil 2026 di Kyoto Sangyo University', 7, 33, 'outbound',
  '2026-09-14', '2026-12-18', 'offline', 'Kyoto Sangyo University', 'JP', 27, '{4}',
  'Program transfer kredit satu semester (kegiatan masih berjalan).',
  null, p_auto => 2, p_files => '{ia}');

select pg_temp.h_act(392, 'Pelatihan Penulisan Artikel Bereputasi bersama LMU Munich', 20, 43, 'inbound',
  '2026-09-29', '2026-09-30', 'hybrid', 'Ruang Seminar LPPM PCU', 'ID', 42, '{4,9}',
  'Pelatihan dua hari strategi publikasi di jurnal internasional bereputasi.',
  pg_temp.h_daysago(0, '09:00'), p_ext => '[{"full_name":"Dr. Lena Becker","institution":"Ludwig Maximilian University of Munich","country_code":"DE","role":"speaker"}]');

select pg_temp.h_act(393, 'Inbound Exchange Semester Ganjil 2026 dari Ateneo de Manila University', 36, 2, 'inbound',
  '2026-08-31', '2026-12-11', 'offline', 'Kampus PCU Siwalankerto', 'ID', 44, '{4}',
  'Mahasiswa Ateneo mengikuti semester di FKIP (kegiatan masih berjalan).',
  null, p_auto => 4, p_files => '{ia}');

select pg_temp.h_act(394, 'Studi Ekskursi Teknik Sipil ke Singapura', 55, 24, 'outbound',
  '2026-09-21', '2026-09-25', 'offline', 'National University of Singapore', 'SG', 36, '{9,11}',
  'Kunjungan proyek MRT, Marina Barrage, dan laboratorium struktur NUS.',
  pg_temp.h_daysago(2, '09:00'), 'pending', pg_temp.h_daysago(2, '09:00'), p_auto => 16, p_auto_staff => 2);

select pg_temp.h_act(395, 'Kuliah Tamu Brand Management dari PT Astra International', 42, 15, 'inbound',
  '2026-09-22', '2026-09-22', 'offline', 'Gedung P PCU', 'ID', 23, '{8}',
  'Kuliah tamu pengelolaan merek otomotif di pasar Indonesia.',
  pg_temp.h_daysago(8, '09:00'), p_ext => '[{"full_name":"Yudha Prakoso, M.M.","institution":"PT Astra International Tbk","country_code":"ID","role":"speaker"}]');

select pg_temp.h_act(396, 'Riset Bersama Energi Surya Atap Kampus dengan NUS', 65, 4, 'inbound',
  '2026-08-03', '2026-09-30', 'hybrid', 'Lab Teknik Elektro PCU', 'ID', 19, '{7,13}',
  'Pengukuran kinerja panel surya atap dan model prediksi produksi energi.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Ryan Tan","institution":"National University of Singapore","country_code":"SG","role":"researcher"}]');

select pg_temp.h_act(397, 'Seminar Internasional Desain Asia 2026', 63, 35, 'inbound',
  '2026-10-21', '2026-10-22', 'hybrid', 'Gedung P PCU', 'ID', 44, '{4,9}',
  'Seminar internasional desain (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(398, 'Kuliah Tamu Kebijakan Publik dari UGM', 33, 15, 'inbound',
  '2026-10-14', '2026-10-14', 'offline', 'Gedung T PCU', 'ID', 33, '{16}',
  'Kuliah tamu mata kuliah wajib kewarganegaraan (direncanakan).',
  null, p_files => '{}');

select pg_temp.h_act(399, 'Academic Exchange DKV di Ateneo de Manila University', 63, 28, 'outbound',
  '2026-08-31', '2026-09-25', 'offline', 'Ateneo de Manila University', 'PH', 44, '{4}',
  'Mahasiswa DKV mengikuti studio desain dan proyek komunitas empat minggu di Ateneo.',
  pg_temp.h_daysago(7, '09:00'), 'approved', pg_temp.h_daysago(2, '14:00'), p_auto => 4);

select pg_temp.h_act(400, 'Joint Seminar Teknologi Pendidikan bersama Ateneo de Manila University', 36, 35, 'inbound',
  '2026-09-29', '2026-09-29', 'online', 'Zoom Meeting', null, 44, '{4}',
  'Seminar daring pemanfaatan AI dalam pembelajaran di sekolah.',
  pg_temp.h_daysago(1, '09:00'), p_ext => '[{"full_name":"Dr. Carlo Mendoza","institution":"Ateneo de Manila University","country_code":"PH","role":"speaker"}]');
select setval('realisasi.activity_code_seq', greatest(400, (select last_value from realisasi.activity_code_seq)));

-- no unintended rule 2.1 conflicts anywhere
select pg_temp.h_assert_no_conflicts();

-- snapshots that no longer match what the scheduled job would freeze (oldest period first)
select pg_temp.h_refreeze_stale('Data historis kegiatan dan peserta ditambahkan (seed).');
select pg_temp.h_date_freeze_notifications();

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
