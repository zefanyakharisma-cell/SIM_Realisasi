-- SIM Realisasi Supabase install, PART 5 OF 5 (commit 86b945f).
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
