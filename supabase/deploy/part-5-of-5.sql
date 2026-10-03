-- SIM Realisasi Supabase install, PART 5 OF 5 (commit fb2a4bc).
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
  ('PG626211', 'Dr. Theresia Santoso, M.M.', 'Prodi Manajemen', 'Ketua Program Studi', 'active'),
  ('PG670883', 'Dr. Stefani Setiawan, M.T.', 'Prodi Manajemen', 'Dosen', 'active'),
  ('PG661938', 'Dr. Rafael Santoso, Ph.D.', 'Prodi Manajemen', 'Lektor Kepala', 'active'),
  ('PG643269', 'Rachel Kusuma, M.Pd.', 'Prodi Manajemen', 'Lektor Kepala', 'active'),
  ('PG641614', 'Lukas Lim, M.T.', 'Prodi Akuntansi', 'Ketua Program Studi', 'active'),
  ('PG641995', 'Devina Wibowo, M.T.', 'Prodi Akuntansi', 'Dosen', 'active'),
  ('PG508242', 'Dr. Evan Hidayat, M.Pd.', 'Prodi Akuntansi', 'Dosen', 'active'),
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
  ('PG505398', 'Ir. Grace Purnomo, M.T.', 'Prodi Kedokteran', 'Ketua Program Studi', 'active'),
  ('PG615813', 'Ir. Daniel Wibowo, M.Ds.', 'Prodi Kedokteran', 'Dosen', 'active'),
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

-- 101: Prodi Kedokteran
select pg_temp.keg(101, 'Cultural Exchange Pendidikan Klinis di Kyoto Sangyo University', 76, 29, 'outbound', '2025-09-01', '2025-09-05', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{3,4}', pg_temp.wib('2025-09-18', '11:30'), 'approved', pg_temp.wib('2025-09-28', '15:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(101, 'approved', '{G61236074,G61228465,G61237319,G61246376,G61246402,G61248311,G61258355}', '{}', '{PG615813,PG505398}', pg_temp.wib('2025-09-18', '11:30'), pg_temp.wib('2025-09-28', '15:30'));

-- 102: Program Studi Informatika
select pg_temp.keg(102, 'Pengembangan Kurikulum Kecerdasan Buatan bersama Kyoto Sangyo', 68, 11, 'outbound', '2025-08-04', '2025-09-01', 'online', 'Zoom Meeting', null, 11, '{4,8,17}', pg_temp.wib('2025-09-19', '09:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}, {"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor"}]'::jsonb);

-- 103: Prodi Akuntansi
select pg_temp.keg(103, 'Cultural Exchange (Inbound) Kyoto Sangyo – Perpajakan Internasional', 6, 29, 'inbound', '2025-09-08', '2025-09-12', 'offline', 'Gedung T PCU', 'ID', 11, '{8,17}', pg_temp.wib('2025-09-22', '14:30'), 'approved', pg_temp.wib('2025-09-30', '12:00'), '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(103, 'approved', '{}', '{X03250305,X03250309,X03250303}', '{PG641614}', pg_temp.wib('2025-09-22', '14:30'), pg_temp.wib('2025-09-30', '12:00'));

-- 104: Program Studi Magister Teknik Industri
select pg_temp.keg(104, 'Seminar Internasional Ergonomi Industri bersama Kyoto Sangyo', 70, 10, 'inbound', '2025-09-22', '2025-09-23', 'online', 'Zoom Meeting', null, 11, '{4,12}', pg_temp.wib('2025-09-26', '08:30'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "speaker"}]'::jsonb);

-- 105: Prodi Akuntansi
select pg_temp.keg(105, 'Workshop Akuntansi Manajemen bersama Kyoto Sangyo', 6, 35, 'inbound', '2025-09-11', '2025-09-12', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 11, '{8,17}', pg_temp.wib('2025-09-30', '14:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "speaker"}]'::jsonb);

-- 106: Program Studi Informatika
select pg_temp.keg(106, 'Magang Internasional Informatika di Kyoto Sangyo University', 68, 21, 'outbound', '2025-08-25', '2025-09-23', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{4,8,9,17}', pg_temp.wib('2025-10-03', '12:45'), 'approved', pg_temp.wib('2025-10-09', '12:30'), '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(106, 'approved', '{B11238162,B11258180,B11228302}', '{}', '{PG591795,PG593383}', pg_temp.wib('2025-10-03', '12:45'), pg_temp.wib('2025-10-09', '12:30'));

-- 107: Prodi Akuntansi
select pg_temp.keg(107, 'Cultural Exchange (Inbound) Kyoto Sangyo – Akuntansi Manajemen', 6, 29, 'inbound', '2025-09-29', '2025-10-05', 'offline', 'Gedung T PCU', 'ID', 11, '{16,17}', pg_temp.wib('2025-10-12', '08:00'), 'approved', pg_temp.wib('2025-10-24', '10:00'), '{ia,ir}', null, '[{"full_name": "Dr. Emi Fujita", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(107, 'approved', '{}', '{X03250303,X03250301,X03250309,X03250307}', '{PG508242}', pg_temp.wib('2025-10-12', '08:00'), pg_temp.wib('2025-10-24', '10:00'));

-- 108: Program Studi Teknik Sipil
select pg_temp.keg(108, 'Short Program Infrastruktur Hijau di Kyoto Sangyo University', 55, 23, 'outbound', '2025-09-22', '2025-10-03', 'offline', 'Kyoto Sangyo University', 'JP', 11, '{6,17}', pg_temp.wib('2025-10-13', '11:00'), 'approved', pg_temp.wib('2025-10-22', '11:30'), '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(108, 'approved', '{A11236394,A11238408,A11248814,A11256435,A11226056}', '{}', '{PG648486,PG564161}', pg_temp.wib('2025-10-13', '11:00'), pg_temp.wib('2025-10-22', '11:30'));

-- 109: Prodi Kedokteran
select pg_temp.keg(109, 'Studi Ekskursi Kedokteran ke Bandung', 76, 24, 'outbound', '2025-10-20', '2025-10-25', 'offline', 'Bandung', 'ID', 28, '{3,4,6}', pg_temp.wib('2025-10-31', '12:00'), 'approved', pg_temp.wib('2025-11-04', '16:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(109, 'approved', '{G61246402,G61257371,G61236074,G61226627,G61237319,G61246376,G61248311,G61246171,G61228465,G61258355}', '{}', '{PG505398}', pg_temp.wib('2025-10-31', '12:00'), pg_temp.wib('2025-11-04', '16:30'));

-- 110: Program Studi Informatika
select pg_temp.keg(110, 'Staff Exchange Dosen Informatika ke National Taiwan University', 68, 3, 'outbound', '2025-10-20', '2025-10-28', 'offline', 'National Taiwan University', 'TW', 30, '{4}', pg_temp.wib('2025-11-02', '12:45'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Wang Mei-Ling", "institution": "National Taiwan University", "country_code": "TW", "role": "other"}]'::jsonb);

-- 111: Prodi Akuntansi
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

-- 120: Prodi Manajemen
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

-- 125: Prodi Akuntansi
select pg_temp.keg(125, 'Magang Internasional Akuntansi di Yonsei University', 6, 21, 'outbound', '2025-10-27', '2025-12-07', 'offline', 'Yonsei University', 'KR', 31, '{4,17}', pg_temp.wib('2025-12-26', '08:00'), 'approved', pg_temp.wib('2026-01-11', '13:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(125, 'approved', '{D32257684,D32257260}', '{}', '{PG641995,PG641614}', pg_temp.wib('2025-12-26', '08:00'), pg_temp.wib('2026-01-11', '13:00'));

-- 126: Program Studi Desain Interior
select pg_temp.keg(126, 'Pengembangan Kurikulum Desain Ruang Publik bersama UGM', 59, 11, 'outbound', '2025-10-27', '2025-12-10', 'online', 'Zoom Meeting', null, 28, '{4,11,17}', pg_temp.wib('2025-12-27', '12:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Rina Kartikasari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other"}, {"full_name": "Dr. Ayu Lestari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "other"}]'::jsonb);

-- 127: Program Studi Sastra Inggris
select pg_temp.keg(127, 'Workshop Penerjemahan Sastra bersama NTU', 61, 35, 'inbound', '2025-12-19', '2025-12-20', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 30, '{4}', pg_temp.wib('2026-01-06', '16:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}, {"full_name": "Dr. Huang Jun-Wei", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]'::jsonb);

-- 128: Prodi Manajemen
select pg_temp.keg(128, 'Staff Exchange Dosen Manajemen ke Chulalongkorn University', 5, 3, 'outbound', '2025-12-08', '2025-12-20', 'hybrid', 'Chulalongkorn University', 'TH', 29, '{8}', pg_temp.wib('2026-01-10', '09:30'), null, null, '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor"}]'::jsonb);

-- 129: Prodi Manajemen
select pg_temp.keg(129, 'Studi Ekskursi Manajemen ke Yonsei University, Seoul', 5, 24, 'outbound', '2025-12-15', '2025-12-22', 'offline', 'Yonsei University, Seoul', 'KR', 31, '{8,12}', pg_temp.wib('2026-01-12', '11:30'), 'approved', pg_temp.wib('2026-01-20', '12:00'), '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(129, 'approved', '{D31237873,D31248243,D31248761,D31227308,D31236401,D31246583,D31237627,D31227742,D31248101,D31248545,D31247059}', '{}', '{PG670883}', pg_temp.wib('2026-01-12', '11:30'), pg_temp.wib('2026-01-20', '12:00'));

-- 130: Prodi Akuntansi
select pg_temp.keg(130, 'Workshop Akuntansi Forensik bersama Astra', 6, 35, 'inbound', '2026-01-05', '2026-01-06', 'offline', 'Gedung Q PCU', 'ID', 12, '{8}', pg_temp.wib('2026-01-13', '16:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}, {"full_name": "Dr. Rina Kartikasari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 131: Prodi Akuntansi
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

-- 144: Prodi Akuntansi
select pg_temp.keg(144, 'Pengembangan Kurikulum Akuntansi Forensik bersama Yonsei', 6, 11, 'outbound', '2025-12-29', '2026-01-21', 'online', 'Zoom Meeting', null, 31, '{16,17}', pg_temp.wib('2026-02-09', '12:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "staff_visitor"}]'::jsonb);

-- 145: Program Studi Pendidikan Guru Pendidikan Anak Usia Dini
select pg_temp.keg(145, 'Kuliah Bersama Pendidikan Inklusif dengan Yonsei', 72, 34, 'inbound', '2026-02-04', '2026-02-04', 'hybrid', 'Gedung T PCU', 'ID', 31, '{10,17}', pg_temp.wib('2026-02-11', '10:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "visiting_lecturer"}]'::jsonb);

-- 146: Prodi Manajemen
select pg_temp.keg(146, 'Pengabdian Masyarakat Strategi Bisnis Asia bersama UGM', 5, 40, 'outbound', '2026-01-22', '2026-01-25', 'hybrid', 'Kampung Batik Jetis', 'ID', 28, '{4,8,17}', pg_temp.wib('2026-02-13', '13:30'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 147: Program Studi Arsitektur
select pg_temp.keg(147, 'Cultural Exchange (Inbound) Kyoto Sangyo – Desain Kota Pesisir', 54, 29, 'inbound', '2026-02-02', '2026-02-10', 'offline', 'Gedung P PCU', 'ID', 11, '{4,11,13}', pg_temp.wib('2026-02-14', '10:30'), 'approved', pg_temp.wib('2026-02-19', '14:30'), '{ia,ir}', null, '[{"full_name": "Dr. Hiroshi Kato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(147, 'approved', '{}', '{X03250303,X03250307,X04260310,X04260306,X03250309}', '{PG635480,PG539055}', pg_temp.wib('2026-02-14', '10:30'), pg_temp.wib('2026-02-19', '14:30'));

-- 148: Prodi Manajemen
select pg_temp.keg(148, 'Student Exchange Bisnis Keluarga di National Taiwan University', 5, 2, 'outbound', '2025-10-20', '2026-01-28', 'offline', 'National Taiwan University', 'TW', 30, '{4,8}', pg_temp.wib('2026-02-18', '14:00'), 'approved', pg_temp.wib('2026-02-28', '09:30'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(148, 'approved', '{D31258938,D31256420}', '{}', '{PG643269}', pg_temp.wib('2026-02-18', '14:00'), pg_temp.wib('2026-02-28', '09:30'));

-- 149: Prodi Manajemen
select pg_temp.keg(149, 'Seminar Internasional Manajemen Rantai Pasok bersama UGM', 5, 10, 'inbound', '2026-02-10', '2026-02-10', 'online', 'Zoom Meeting', null, 28, '{8,12}', pg_temp.wib('2026-02-19', '14:45'), null, null, '{ia,ir}', null, '[{"full_name": "Hendro Saputro, S.E., M.M.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}, {"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "Universitas Gadjah Mada", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 150: Program Studi Magister Teknik Sipil
select pg_temp.keg(150, 'Staff Exchange Dosen Magister Teknik Sipil ke PT Astra International Tbk', 56, 3, 'outbound', '2026-02-16', '2026-02-20', 'offline', 'PT Astra International Tbk', 'ID', 12, '{6}', pg_temp.wib('2026-02-27', '15:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 151: Prodi Akuntansi
select pg_temp.keg(151, 'Kuliah Tamu Perpajakan Internasional dari Chulalongkorn University', 6, 15, 'inbound', '2026-02-14', '2026-02-15', 'online', 'Zoom Meeting', null, 29, '{4,8,16,17}', pg_temp.wib('2026-03-02', '10:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]'::jsonb);

-- 152: Program Studi Arsitektur
select pg_temp.keg(152, 'Kuliah Tamu Konservasi Bangunan Bersejarah dari National University of Singapore', 54, 15, 'inbound', '2026-03-05', '2026-03-06', 'offline', 'Gedung Q PCU', 'ID', 19, '{4,11,17}', pg_temp.wib('2026-03-26', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 153: Program Studi Teknik Mesin
select pg_temp.keg(153, 'Kuliah Bersama Manufaktur Aditif dengan Chulalongkorn', 69, 34, 'inbound', '2026-03-21', '2026-03-21', 'offline', 'Gedung P PCU', 'ID', 29, '{4,7,12}', pg_temp.wib('2026-03-30', '13:15'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "visiting_lecturer"}]'::jsonb);

-- 154: Prodi Kedokteran
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

-- 163: Prodi Manajemen
select pg_temp.keg(163, 'Academic Visit Manajemen ke PT Astra International Tbk', 5, 27, 'outbound', '2026-05-11', '2026-05-12', 'offline', 'PT Astra International Tbk', 'ID', 12, '{8,9}', pg_temp.wib('2026-06-01', '12:15'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ayu Lestari", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 164: Program Studi Desain Interior
select pg_temp.keg(164, 'Cultural Exchange (Inbound) NTU – Ilustrasi dan Narasi Visual', 59, 29, 'inbound', '2026-05-11', '2026-05-18', 'offline', 'Gedung P PCU', 'ID', 15, '{4,9,12}', pg_temp.wib('2026-06-02', '12:00'), 'approved', pg_temp.wib('2026-06-20', '10:00'), '{ia,ir}', null, '[{"full_name": "Dr. Lin Chia-Hao", "institution": "National Taiwan University", "country_code": "TW", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(164, 'approved', '{}', '{X04260314,X03250319,X03250315,X04260318,X04260322}', '{PG600979}', pg_temp.wib('2026-06-02', '12:00'), pg_temp.wib('2026-06-20', '10:00'));

-- 165: Prodi Kedokteran
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

-- 169: Prodi Akuntansi
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

-- 176: Prodi Akuntansi
select pg_temp.keg(176, 'Magang Industri Akuntansi di PT Unilever Indonesia Tbk', 6, 21, 'outbound', '2026-04-13', '2026-06-03', 'offline', 'PT Unilever Indonesia Tbk', 'ID', 21, '{16}', pg_temp.wib('2026-06-17', '09:30'), 'approved', pg_temp.wib('2026-07-05', '12:30'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(176, 'approved', '{D32227188,D32248005,D32227795,D32257463,D32237743}', '{}', '{PG641614}', pg_temp.wib('2026-06-17', '09:30'), pg_temp.wib('2026-07-05', '12:30'));

-- 177: Prodi Manajemen
select pg_temp.keg(177, 'Kuliah Bersama Manajemen SDM Global dengan NUS', 5, 34, 'inbound', '2026-06-12', '2026-06-13', 'hybrid', 'Gedung Q PCU', 'ID', 19, '{4,9,12,17}', pg_temp.wib('2026-06-17', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "visiting_lecturer"}]'::jsonb);

-- 178: Prodi Manajemen
select pg_temp.keg(178, 'Studi Ekskursi Manajemen ke Yogyakarta', 5, 24, 'outbound', '2026-06-07', '2026-06-09', 'offline', 'Yogyakarta', 'ID', 12, '{4,9,17}', pg_temp.wib('2026-06-19', '16:00'), 'approved', pg_temp.wib('2026-07-07', '14:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(178, 'approved', '{D31237873,D31248101,D31256312,D31237888,D31247028,D31236101,D31228283,D31248402,D31258883,D31227308}', '{}', '{PG661938}', pg_temp.wib('2026-06-19', '16:00'), pg_temp.wib('2026-07-07', '14:00'));

-- 179: Prodi Manajemen
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

-- 181: Prodi Manajemen
select pg_temp.keg(181, 'Workshop Manajemen Rantai Pasok bersama NUS', 5, 35, 'inbound', '2026-06-21', '2026-06-23', 'hybrid', 'Kampus PCU Siwalankerto', 'ID', 19, '{9}', pg_temp.wib('2026-06-26', '08:30'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}, {"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 182: Program Studi Teknik Sipil
select pg_temp.keg(182, 'Academic Exchange (Inbound) Kyoto Sangyo – Manajemen Konstruksi', 55, 28, 'inbound', '2026-03-16', '2026-06-14', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 11, '{6,11}', pg_temp.wib('2026-06-27', '11:00'), 'approved', pg_temp.wib('2026-07-08', '14:00'), '{ia,ir}', null, '[{"full_name": "Prof. Kenji Watanabe", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(182, 'approved', '{}', '{X03250311,X04260306,X03250301,X03250307}', '{}', pg_temp.wib('2026-06-27', '11:00'), pg_temp.wib('2026-07-08', '14:00'));

-- 183: Program Studi Informatika
select pg_temp.keg(183, 'Student Exchange Kecerdasan Buatan di National Taiwan University', 68, 2, 'outbound', '2026-03-02', '2026-06-20', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{4,8}', pg_temp.wib('2026-06-28', '13:45'), 'revision_requested', pg_temp.wib('2026-07-04', '13:30'), '{ia,ir}', 'Dua NRP tidak sesuai surat tugas; mohon perbarui data peserta.', '[]'::jsonb);
select pg_temp.peserta(183, 'revision_requested', '{B11247302,B11258007,B11257605,B11236858}', '{}', '{PG591795}', pg_temp.wib('2026-06-28', '13:45'), pg_temp.wib('2026-07-04', '13:30'));

-- 184: Prodi Akuntansi
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

-- 190: Prodi Kedokteran
select pg_temp.keg(190, 'Kuliah Tamu Kesehatan Gigi Komunitas dari National University of Singapore', 76, 15, 'inbound', '2026-05-22', '2026-05-22', 'offline', 'Ruang Seminar Gedung W PCU', 'ID', 19, '{4,6}', pg_temp.wib('2026-07-10', '09:15'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Rajesh Kumar", "institution": "National University of Singapore", "country_code": "SG", "role": "speaker"}]'::jsonb);

-- 191: Program Studi Informatika
select pg_temp.keg(191, 'Seminar Internasional Komputasi Awan bersama NTU', 68, 10, 'inbound', '2026-06-30', '2026-06-30', 'hybrid', 'Kampus PCU Siwalankerto', 'ID', 15, '{4,8,9}', pg_temp.wib('2026-07-13', '10:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Chen Yu-Ting", "institution": "National Taiwan University", "country_code": "TW", "role": "speaker"}]'::jsonb);

-- 192: Program Studi Magister Manajemen
select pg_temp.keg(192, 'Kuliah Tamu Pemasaran Berkelanjutan dari Yonsei University', 48, 15, 'inbound', '2026-06-26', '2026-06-26', 'offline', 'Kampus PCU Siwalankerto', 'ID', 31, '{4,9,12,17}', pg_temp.wib('2026-07-14', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Park Jae-hyun", "institution": "Yonsei University", "country_code": "KR", "role": "speaker"}]'::jsonb);

-- 193: Prodi Manajemen
select pg_temp.keg(193, 'Seminar Internasional Manajemen Rantai Pasok bersama Astra', 5, 10, 'inbound', '2026-07-06', '2026-07-07', 'offline', 'Gedung P PCU', 'ID', 12, '{4,8,12}', pg_temp.wib('2026-07-15', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dewi Anggraini, S.T., M.B.A.", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "speaker"}]'::jsonb);

-- 194: Prodi Manajemen
select pg_temp.keg(194, 'Cultural Exchange (Inbound) Chulalongkorn – Kewirausahaan Digital', 5, 29, 'inbound', '2026-05-18', '2026-05-25', 'offline', 'Gedung Q PCU', 'ID', 25, '{4,9,17}', pg_temp.wib('2026-07-19', '10:00'), 'approved', pg_temp.wib('2026-07-25', '16:30'), '{ia,ir}', null, '[{"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(194, 'approved', '{}', '{X03250347,X04260348,X03250343}', '{PG643269,PG661938}', pg_temp.wib('2026-07-19', '10:00'), pg_temp.wib('2026-07-25', '16:30'));

-- 195: Program Studi Desain Interior
select pg_temp.keg(195, 'Staff Exchange Dosen Desain Interior ke PT Unilever Indonesia Tbk', 59, 3, 'outbound', '2026-06-01', '2026-06-13', 'hybrid', 'PT Unilever Indonesia Tbk', 'ID', 21, '{4,12}', pg_temp.wib('2026-07-24', '09:45'), null, null, '{ia,ir}', null, '[{"full_name": "Dra. Sri Wahyuni, M.Si.", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "staff_visitor"}, {"full_name": "Prof. Bambang Wicaksono", "institution": "PT Unilever Indonesia Tbk", "country_code": "ID", "role": "other"}]'::jsonb);

-- 196: Prodi Kedokteran
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

-- 202: Prodi Manajemen
select pg_temp.keg(202, 'Immersion Program Manajemen Rantai Pasok di Yonsei University', 5, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University', 'KR', 31, '{4,8,9}', pg_temp.wib('2026-08-24', '10:00'), 'approved', pg_temp.wib('2026-08-28', '12:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(202, 'approved', '{D31236101,D31256312,D31258008,D31227742,D31248399,D31258883,D31248402,D31247059,D31256420,D31228283,D31237873,D31248761,D31237541,D31236401}', '{}', '{PG643269}', pg_temp.wib('2026-08-24', '10:00'), pg_temp.wib('2026-08-28', '12:00'));

-- 203: Program Studi Teknik Sipil
select pg_temp.keg(203, 'Studi Ekskursi Teknik Sipil ke Chulalongkorn University, Bangkok', 55, 24, 'outbound', '2026-08-10', '2026-08-14', 'offline', 'Chulalongkorn University, Bangkok', 'TH', 25, '{4,6,11}', pg_temp.wib('2026-08-24', '12:00'), 'pending', pg_temp.wib('2026-08-24', '12:00'), '{ia,ir}', null, '[{"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "staff_visitor", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(203, 'pending', '{A11246886,A11247207,A11256435,A11248814,A11258276,A11238958,A11238408,A11236661,A11226056,A11227441,A11236394,A11246063}', '{}', '{PG648486,PG564161}', pg_temp.wib('2026-08-24', '12:00'), null);

-- 204: Program Studi Magister Manajemen
select pg_temp.keg(204, 'Immersion Program Manajemen Rantai Pasok (Magister Manajemen)', 48, 22, 'outbound', '2026-08-10', '2026-08-21', 'offline', 'Yonsei University', 'KR', 31, '{4,17}', pg_temp.wib('2026-08-27', '10:00'), 'pending', pg_temp.wib('2026-08-27', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(204, 'pending', '{D31236101,D31256312,H71258825}', '{}', '{}', pg_temp.wib('2026-08-27', '10:00'), null);
select realisasi._scan_conflicts(pg_temp.aid(204)) where not exists (select 1 from realisasi.participant_conflicts where pg_temp.aid(204) in (activity_a, activity_b));

-- 205: Prodi Kedokteran
select pg_temp.keg(205, 'Short Program Pendidikan Klinis di Kyoto Sangyo University', 76, 23, 'outbound', '2026-08-10', '2026-08-23', 'offline', 'Kyoto Sangyo University, Kyoto', 'JP', 11, '{4,6,17}', pg_temp.wib('2026-08-29', '10:00'), 'pending', pg_temp.wib('2026-08-29', '10:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(205, 'pending', '{G61257371,G61248311,G61258355,G61246171,G61237319,G61226627,G61246376,G61228465,G61246402,G61236074}', '{}', '{PG615813}', pg_temp.wib('2026-08-29', '10:00'), null);

-- 206: Prodi Akuntansi
select pg_temp.keg(206, 'Immersion Program Akuntansi Forensik di Yonsei University', 6, 22, 'outbound', '2026-08-17', '2026-08-27', 'offline', 'Yonsei University', 'KR', 31, '{8,16}', pg_temp.wib('2026-08-29', '15:00'), 'approved', pg_temp.wib('2026-09-01', '14:30'), '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Lee Dong-hoon", "institution": "Yonsei University", "country_code": "KR", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(206, 'approved', '{D32247516,D32227188,D32228238,D32237065,D32248238,D32247773,D32227795,D32258446,D32237743}', '{}', '{PG641614}', pg_temp.wib('2026-08-29', '15:00'), pg_temp.wib('2026-09-01', '14:30'));

-- 207: Program Studi Sastra Inggris
select pg_temp.keg(207, 'Staff Exchange Dosen Sastra Inggris ke Kyoto Sangyo University', 61, 3, 'outbound', '2026-08-17', '2026-08-24', 'hybrid', 'Kyoto Sangyo University', 'JP', 11, '{4,10}', pg_temp.wib('2026-08-30', '08:00'), null, null, '{ia,ir}', null, '[{"full_name": "Assoc. Prof. Mika Sato", "institution": "Kyoto Sangyo University", "country_code": "JP", "role": "other"}]'::jsonb);

-- 208: Program Studi Teknik Sipil
select pg_temp.keg(208, 'Seminar Internasional Rekayasa Gempa bersama Chulalongkorn', 55, 10, 'inbound', '2026-08-19', '2026-08-20', 'hybrid', 'Gedung T PCU', 'ID', 25, '{4,9,11}', pg_temp.wib('2026-08-30', '12:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Ploy Charoenkul", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Prof. Somchai Thongchai", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}, {"full_name": "Asst. Prof. Kanokwan Srisuk", "institution": "Chulalongkorn University", "country_code": "TH", "role": "speaker"}]'::jsonb);

-- 209: Program Studi Magister Teknik Sipil
select pg_temp.keg(209, 'Staff Exchange Dosen Magister Teknik Sipil ke Yonsei University', 56, 3, 'outbound', '2026-08-24', '2026-08-30', 'hybrid', 'Yonsei University', 'KR', 31, '{4,9,11}', pg_temp.wib('2026-09-09', '09:00'), null, null, '{ia,ir}', null, '[{"full_name": "Dr. Kim Soo-yeon", "institution": "Yonsei University", "country_code": "KR", "role": "staff_visitor"}]'::jsonb);

-- 210: Prodi Manajemen
select pg_temp.keg(210, 'Immersion Program Manajemen Rantai Pasok di National Taiwan University', 5, 22, 'outbound', '2026-09-07', '2026-09-14', 'offline', 'National Taiwan University, Taipei', 'TW', 15, '{8,12}', pg_temp.wib('2026-09-16', '11:00'), 'approved', pg_temp.wib('2026-09-20', '11:00'), '{ia,ir}', null, '[]'::jsonb);
select pg_temp.peserta(210, 'approved', '{D31248101,D31258938,D31258008,D31236401,D31236200,D31237873,D31227742,D31236101,D31248761,D31237541,D31228357}', '{}', '{PG643269}', pg_temp.wib('2026-09-16', '11:00'), pg_temp.wib('2026-09-20', '11:00'));

-- 211: Prodi Manajemen
select pg_temp.keg(211, 'Pengabdian Masyarakat Kewirausahaan Digital bersama Astra', 5, 40, 'outbound', '2026-09-13', '2026-09-15', 'offline', 'Kelurahan Kenjeran', 'ID', 12, '{4,9,12}', pg_temp.wib('2026-09-20', '13:00'), null, null, '{ia,ir}', null, '[{"full_name": "Prof. Bambang Wicaksono", "institution": "PT Astra International Tbk", "country_code": "ID", "role": "staff_visitor"}]'::jsonb);

-- 212: Prodi Akuntansi
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

-- 216: Prodi Manajemen
select pg_temp.keg(216, 'Magang Industri Manajemen di Universitas Gadjah Mada', 5, 21, 'outbound', '2026-08-03', '2026-09-29', 'offline', 'Universitas Gadjah Mada', 'ID', 28, '{9,17}', pg_temp.wib('2026-10-02', '10:00'), 'revision_requested', pg_temp.wib('2026-10-02', '11:00'), '{ia,ir}', 'Dua NRP tidak sesuai surat tugas; mohon perbarui data peserta.', '[]'::jsonb);
select pg_temp.peserta(216, 'revision_requested', '{D31248545,D31246583,D31247028,D31228515,D31236499}', '{}', '{PG643269,PG626211}', pg_temp.wib('2026-10-02', '10:00'), pg_temp.wib('2026-10-02', '11:00'));

-- 217: Program Studi Desain Komunikasi Visual
select pg_temp.keg(217, 'Kuliah Tamu Desain Berkelanjutan dari Ludwig Maximilian University of Munich', 63, 15, 'inbound', '2026-09-08', '2026-09-09', 'offline', 'Gedung Q PCU', 'ID', 42, '{4,11,17}', null, null, null, '{}', null, '[{"full_name": "Prof. Dr. Markus Klein", "institution": "Ludwig Maximilian University of Munich", "country_code": "DE", "role": "speaker"}]'::jsonb);

-- 218: Prodi Manajemen
select pg_temp.keg(218, 'Studi Ekskursi Manajemen ke Chulalongkorn University', 5, 24, 'outbound', '2026-09-07', '2026-09-12', 'offline', 'Chulalongkorn University', 'TH', 25, '{4,8,12}', null, null, null, '{ia}', null, '[]'::jsonb);
select pg_temp.peserta(218, 'draft', '{D31227308,D31248011,D31258883,D31237888,D31248402,D31248243,D31256420,D31228283,D31247059,D31256312,D31237627,D31248399}', '{}', '{PG643269}', null, null);

-- 219: Program Studi Teknik Mesin
select pg_temp.keg(219, 'Short Program (Inbound) NUS – Manufaktur Aditif', 69, 23, 'inbound', '2026-09-14', '2026-09-23', 'offline', 'Gedung T PCU', 'ID', 36, '{7,12}', null, null, null, '{}', null, '[{"full_name": "Prof. Tan Wee Kiat", "institution": "National University of Singapore", "country_code": "SG", "role": "other", "notes": "Koordinator program dari mitra"}]'::jsonb);
select pg_temp.peserta(219, 'draft', '{}', '{X03250335,X04260332,X03250339,X04260338,X04260340,X04260334}', '{}', null, null);

-- 220: Prodi Akuntansi
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
